package ir.channel.telegram_news

import android.content.Context
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets

/**
 * Embedded WireGuard engine for Gozar. It uses WireGuard's official Android
 * tunnel library and mirrors Gozar's existing all/selected-app routing policy.
 */
object WireGuardController {
    @Volatile var stage: String = "off"
    @Volatile var detail: String = "WireGuard خاموش است."
    @Volatile private var operationId: Int = 0

    private val lock = Any()
    private var backend: GoBackend? = null

    private val tunnel = object : Tunnel {
        override fun getName(): String = "gozar_wg"

        override fun onStateChange(newState: Tunnel.State) {
            if (newState == Tunnel.State.UP) {
                stage = "running"
                detail = "تونل WireGuard فعال است."
            } else if (stage != "error") {
                stage = "off"
                detail = "WireGuard خاموش است."
            }
        }
    }

    private fun backend(context: Context): GoBackend = synchronized(lock) {
        backend ?: GoBackend(context.applicationContext).also { backend = it }
    }

    private fun applyRouting(
        raw: String,
        policy: VpnRoutingPolicy,
        context: Context
    ): String {
        val lines = raw.replace("\r\n", "\n").lines()
            .filterNot {
                val trimmed = it.trim()
                trimmed.startsWith("IncludedApplications", ignoreCase = true) ||
                    trimmed.startsWith("ExcludedApplications", ignoreCase = true)
            }
            .toMutableList()

        val interfaceIndex = lines.indexOfFirst {
            it.trim().equals("[Interface]", ignoreCase = true)
        }
        require(interfaceIndex >= 0) { "WireGuard [Interface] section is missing" }

        val packages = if (policy.mode == "selected") {
            policy.packages.distinct()
        } else {
            (listOf(context.packageName) +
                AutomaticBypassPolicy.installedPackages(
                    context.packageManager, context.packageName
                )).distinct()
        }
        if (packages.isNotEmpty()) {
            val key = if (policy.mode == "selected") {
                "IncludedApplications"
            } else {
                "ExcludedApplications"
            }
            lines.add(interfaceIndex + 1, "$key = " + packages.joinToString(", "))
        }
        return lines.joinToString("\n")
    }

    fun start(context: Context, rawConfig: String, policy: VpnRoutingPolicy) {
        val id: Int
        synchronized(lock) {
            if (stage == "running" || stage == "starting" || stage == "stopping") {
                throw IllegalStateException("WireGuard is busy")
            }
            id = ++operationId
            stage = "starting"
            detail = "در حال راه‌اندازی موتور WireGuard…"
        }
        Thread({
            try {
                val routed = applyRouting(rawConfig, policy, context)
                val config = Config.parse(ByteArrayInputStream(
                    routed.toByteArray(StandardCharsets.UTF_8)
                ))
                synchronized(lock) {
                    if (id != operationId) return@Thread
                }
                val activeBackend = backend(context)
                activeBackend.setState(tunnel, Tunnel.State.UP, config)
                synchronized(lock) {
                    if (id != operationId) {
                        try {
                            activeBackend.setState(tunnel, Tunnel.State.DOWN, null)
                        } catch (_: Throwable) { }
                        return@Thread
                    }
                    stage = "running"
                    detail = "تونل WireGuard فعال است."
                }
            } catch (error: Throwable) {
                synchronized(lock) {
                    if (id == operationId) {
                        stage = "error"
                        detail = "WireGuard اجرا نشد: " + error.javaClass.simpleName
                    }
                }
            }
        }, "gozar-wireguard-start").start()
    }

    fun stop(context: Context) {
        val id: Int
        val activeBackend: GoBackend?
        synchronized(lock) {
            id = ++operationId
            activeBackend = backend
            if (stage == "off" && activeBackend == null) {
                detail = "WireGuard خاموش است."
                return
            }
            stage = "stopping"
            detail = "در حال قطع WireGuard…"
        }
        Thread({
            try {
                activeBackend?.setState(tunnel, Tunnel.State.DOWN, null)
            } catch (_: Throwable) {
                // If Android already tore down the VPN service, report OFF.
            } finally {
                synchronized(lock) {
                    if (id == operationId) {
                        stage = "off"
                        detail = "WireGuard خاموش است."
                    }
                }
            }
        }, "gozar-wireguard-stop").start()
    }
}

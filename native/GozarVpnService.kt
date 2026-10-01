package ir.channel.telegram_news

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import go.Seq
import java.util.concurrent.atomic.AtomicBoolean
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray

/**
 * Full-device Xray TUN service for Gozar.
 * Gozar's own UID is excluded so the embedded core can reach the network
 * without tunneling its sockets back into itself.
 */
class GozarVpnService : VpnService() {
    companion object {
        const val EXTRA_CONFIG = "xray_config"
        const val ACTION_STOP =
            "ir.channel.telegram_news.ACTION_STOP_GOZAR_VPN"

        @Volatile var stage = "off"
        @Volatile var detail = "VPN خاموش است."
        @Volatile private var activeService: GozarVpnService? = null

        private const val NOTIFICATION_CHANNEL =
            "gozar_xray_vpn"
        private const val NOTIFICATION_ID = 19742

        fun measureActiveConnection(done: (Long?) -> Unit) {
            val service = activeService
            if (stage != "running" || service == null) {
                done(null)
                return
            }
            service.measureConnection(done)
        }
    }

    private val resourceLock = Any()
    @Volatile private var stopping = false
    private var tunnel: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private var startupThread: Thread? = null
    private val probing = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun measureConnection(done: (Long?) -> Unit) {
        val selectedCore = synchronized(resourceLock) {
            if (stopping || stage != "running") null else core
        }
        if (selectedCore == null ||
            !probing.compareAndSet(false, true)) {
            done(null)
            return
        }

        val delivered = AtomicBoolean(false)
        mainHandler.postDelayed({
            if (delivered.compareAndSet(false, true)) {
                done(null)
            }
        }, 12000L)

        Thread({
            val delay = try {
                selectedCore
                    .measureDelay(
                        "https://www.gstatic.com/generate_204"
                    )
                    .takeIf { it >= 0L }
            } catch (_: Throwable) {
                null
            }
            val stillCurrent = synchronized(resourceLock) {
                !stopping &&
                    stage == "running" &&
                    core === selectedCore
            }
            probing.set(false)
            mainHandler.post {
                if (delivered.compareAndSet(false, true)) {
                    done(if (stillCurrent) delay else null)
                }
            }
        }, "gozar-xray-health").start()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        if (intent?.action == ACTION_STOP) {
            stopVpn("درخواست قطع اتصال")
            stopSelf()
            return START_NOT_STICKY
        }

        if (stopping) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (startupThread != null) {
            return START_NOT_STICKY
        }

        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrBlank() ||
            VpnService.prepare(this) != null) {
            stage = "error"
            detail =
                "مجوز VPN یا کانفیگ Xray در دسترس نیست."
            stopSelf()
            return START_NOT_STICKY
        }

        createForegroundNotification()
        activeService = this
        stage = "starting"
        detail =
            "در حال راه‌اندازی Xray-core و تونل اندروید…"

        startupThread = Thread({
            try {
                Seq.setContext(applicationContext)
                Libv2ray.initCoreEnv(
                    filesDir.absolutePath,
                    ""
                )
                if (stopping) return@Thread

                val builder = Builder()
                    .setSession(
                        applicationInfo
                            .loadLabel(packageManager)
                            .toString()
                    )
                    .setMtu(1500)
                    .addAddress("10.25.0.2", 30)
                    .addRoute("0.0.0.0", 0)
                    .addAddress("fd10:25::2", 126)
                    .addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("2606:4700:4700::1111")

                val directPackages = listOf(packageName) +
                    GozarDirectAppPolicy.installedPackages(
                        packageManager,
                        packageName
                    )
                directPackages.distinct().forEach { pkg ->
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                        // An app can be removed between discovery and TUN setup.
                    }
                }

                val fd = builder.establish()
                    ?: throw IllegalStateException(
                        "Android did not establish TUN"
                    )

                synchronized(resourceLock) {
                    if (stopping) {
                        fd.close()
                        return@Thread
                    }
                    tunnel = fd
                }

                val controller =
                    Libv2ray.newCoreController(
                        object : CoreCallbackHandler {
                            override fun startup(): Long = 0
                            override fun shutdown(): Long = 0
                            override fun onEmitStatus(
                                code: Long,
                                message: String?
                            ): Long = 0
                        }
                    )

                synchronized(resourceLock) {
                    if (stopping) return@Thread
                    core = controller
                }

                controller.startLoop(config, fd.fd)

                if (stopping) {
                    try {
                        controller.stopLoop()
                    } catch (_: Throwable) {
                    }
                    return@Thread
                }

                synchronized(resourceLock) {
                    if (!stopping) {
                        stage = "running"
                        detail = "Xray-core متصل است؛ برنامه‌های بانکی و سرویس‌های ایرانی مستقیم هستند."
                    }
                }
            } catch (error: Throwable) {
                if (!stopping) {
                    stage = "error"
                    detail =
                        "Xray-core اجرا نشد: " +
                            error.javaClass.simpleName
                    stopSelf()
                }
            }
        }, "gozar-xray-start").also { it.start() }

        return START_NOT_STICKY
    }

    private fun stopVpn(reason: String) {
        val startup: Thread?
        val failureDetail: String?
        synchronized(resourceLock) {
            if (stopping) return
            failureDetail =
                if (stage == "error" &&
                    reason != "درخواست قطع اتصال") {
                    detail
                } else {
                    null
                }
            stopping = true
            stage = "stopping"
            detail = reason
            startup = startupThread
            try {
                tunnel?.close()
            } catch (_: Exception) {
            }
            tunnel = null
        }

        Thread({
            try {
                startup?.join(500)
                val active = synchronized(resourceLock) {
                    val value = core
                    core = null
                    value
                }
                try {
                    active?.stopLoop()
                } catch (_: Throwable) {
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } finally {
                stage =
                    if (failureDetail != null) "error" else "off"
                detail =
                    failureDetail ?: "VPN خاموش است."
            }
        }, "gozar-xray-stop").start()
    }

    private fun createForegroundNotification() {
        val manager =
            getSystemService(NotificationManager::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "اتصال VPN گذر",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(
                    this,
                    NOTIFICATION_CHANNEL
                )
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("VPN گذر")
            .setContentText("Xray-core فعال است")
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(
                NOTIFICATION_ID,
                notification
            )
        }
    }

    override fun onRevoke() {
        stopVpn("مجوز VPN توسط اندروید لغو شد.")
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        if (activeService === this) {
            activeService = null
        }
        stopVpn("سرویس VPN اندروید متوقف شد.")
        super.onDestroy()
    }
}

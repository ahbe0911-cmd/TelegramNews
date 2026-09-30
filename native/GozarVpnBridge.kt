package ir.channel.telegram_news

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Xray-only VPN bridge used from the Settings screen.
 * This bridge exposes only the embedded Xray tunnel lifecycle.
 */
object GozarVpnBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/gozar_vpn"
    private const val REQUEST_VPN = 7412

    private var waitingConfig: String? = null

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "stage" to GozarVpnService.stage,
                            "detail" to GozarVpnService.detail,
                        )
                    )

                    "measureConnection" -> {
                        GozarVpnService.measureActiveConnection { delay ->
                            activity.runOnUiThread {
                                result.success(
                                    mapOf(
                                        "ok" to (delay != null),
                                        "latencyMs" to delay,
                                    )
                                )
                            }
                        }
                    }

                    "stop" -> {
                        waitingConfig = null
                        if (GozarVpnService.stage == "consent") {
                            GozarVpnService.stage = "off"
                            GozarVpnService.detail = "VPN خاموش است."
                        }
                        if (GozarVpnService.stage == "off") {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            activity.startService(
                                Intent(activity, GozarVpnService::class.java)
                                    .setAction(GozarVpnService.ACTION_STOP)
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            val stopped = activity.stopService(
                                Intent(activity, GozarVpnService::class.java)
                            )
                            if (stopped) {
                                result.success(null)
                            } else {
                                result.error(
                                    "VPN_STOP_FAILED",
                                    "Android could not stop the VPN service",
                                    null
                                )
                            }
                        }
                    }

                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank() ||
                            config.length > 1024 * 1024) {
                            result.error(
                                "INVALID_CONFIG",
                                "Invalid Xray JSON",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        if (GozarVpnService.stage in setOf(
                                "running",
                                "starting",
                                "stopping",
                                "consent"
                            )
                        ) {
                            result.error(
                                "VPN_BUSY",
                                "Wait for the current VPN operation to finish",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val approval = VpnService.prepare(activity)
                            if (approval != null) {
                                waitingConfig = config
                                GozarVpnService.stage = "consent"
                                GozarVpnService.detail =
                                    "در انتظار مجوز VPN اندروید…"
                                @Suppress("DEPRECATION")
                                activity.startActivityForResult(
                                    approval,
                                    REQUEST_VPN
                                )
                                result.success("permission_requested")
                            } else {
                                launch(activity, config)
                                result.success("starting")
                            }
                        } catch (error: Exception) {
                            waitingConfig = null
                            GozarVpnService.stage = "error"
                            GozarVpnService.detail =
                                "شروع VPN انجام نشد: " +
                                    error.javaClass.simpleName
                            result.error(
                                "VPN_START_FAILED",
                                "Could not open Android VPN",
                                null
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    fun onActivityResult(
        activity: MainActivity,
        requestCode: Int,
        resultCode: Int
    ): Boolean {
        if (requestCode != REQUEST_VPN) return false
        val config = waitingConfig
        waitingConfig = null
        if (resultCode == Activity.RESULT_OK && config != null) {
            try {
                launch(activity, config)
            } catch (error: Exception) {
                GozarVpnService.stage = "error"
                GozarVpnService.detail =
                    "شروع VPN انجام نشد: " +
                        error.javaClass.simpleName
            }
        } else {
            GozarVpnService.stage = "off"
            GozarVpnService.detail =
                "مجوز VPN اندروید صادر نشد."
        }
        return true
    }

    private fun launch(activity: Activity, config: String) {
        val intent = Intent(activity, GozarVpnService::class.java)
            .putExtra(GozarVpnService.EXTRA_CONFIG, config)
        GozarVpnService.stage = "starting"
        GozarVpnService.detail =
            "در حال راه‌اندازی Xray-core…"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }
}

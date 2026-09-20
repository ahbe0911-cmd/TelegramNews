package ir.channel.telegram_news

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * User consent is obtained through the Android system dialog. It is not a
 * pretend VPN toggle: the foreground service starts only after authorization.
 */
object SystemVpnBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/system_vpn"
    private const val REQUEST_VPN = 7301
    private var waitingConfig: String? = null

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(mapOf(
                        "stage" to SystemVpnService.stage,
                        "detail" to SystemVpnService.detail
                    ))
                    "stop" -> {
                        waitingConfig = null
                        activity.stopService(Intent(activity, SystemVpnService::class.java))
                        result.success(null)
                    }
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank() || config.length > 1024 * 1024) {
                            result.error("INVALID_CONFIG", "Invalid Xray JSON", null)
                            return@setMethodCallHandler
                        }
                        if (SystemVpnService.stage == "running" ||
                            SystemVpnService.stage == "starting") {
                            result.error("VPN_BUSY", "Disconnect the existing VPN first", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val approval = VpnService.prepare(activity)
                            if (approval != null) {
                                waitingConfig = config
                                SystemVpnService.stage = "consent"
                                SystemVpnService.detail = "Waiting for Android VPN permission"
                                @Suppress("DEPRECATION")
                                activity.startActivityForResult(approval, REQUEST_VPN)
                                result.success("permission_requested")
                            } else {
                                launch(activity, config)
                                result.success("starting")
                            }
                        } catch (e: Exception) {
                            waitingConfig = null
                            SystemVpnService.stage = "error"
                            SystemVpnService.detail = e.javaClass.simpleName
                            result.error("VPN_START_FAILED", "Could not open Android VPN", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    fun onActivityResult(activity: MainActivity, requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        val config = waitingConfig
        waitingConfig = null
        if (resultCode == Activity.RESULT_OK && config != null) {
            try {
                launch(activity, config)
            } catch (e: Exception) {
                SystemVpnService.stage = "error"
                SystemVpnService.detail = e.javaClass.simpleName
            }
        } else {
            SystemVpnService.stage = "off"
            SystemVpnService.detail = "Android VPN permission was not granted"
        }
        return true
    }

    private fun launch(activity: Activity, config: String) {
        val intent = Intent(activity, SystemVpnService::class.java)
            .putExtra(SystemVpnService.EXTRA_CONFIG, config)
        SystemVpnService.stage = "starting"
        SystemVpnService.detail = "Starting Android VPN service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }
}

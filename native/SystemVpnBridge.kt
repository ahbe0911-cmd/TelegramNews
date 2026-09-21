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
    private var waitingRouting: VpnRoutingPolicy? = null

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startInternal" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank() || config.length > 1024 * 1024) {
                            result.error("BAD_INTERNAL_CONFIG", "Invalid internal Xray config", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(activity, InternalTelegramProxyService::class.java)
                                .putExtra(InternalTelegramProxyService.EXTRA_CONFIG, config)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                activity.startForegroundService(intent)
                            } else {
                                activity.startService(intent)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INTERNAL_START_FAILED",
                                "Cannot start separate Telegram Xray service", null)
                        }
                    }
                    "stopInternal" -> {
                        activity.stopService(Intent(activity,
                            InternalTelegramProxyService::class.java))
                        result.success(null)
                    }
                    "installedApps" -> {
                        val launcher = Intent(Intent.ACTION_MAIN)
                            .addCategory(Intent.CATEGORY_LAUNCHER)
                        // Only launchable apps are visible on Android 11+.
                        val entries = activity.packageManager.queryIntentActivities(
                            launcher, 0
                        ).mapNotNull { info ->
                            val pkg = info.activityInfo.packageName
                            if (pkg == activity.packageName) null else mapOf(
                                "package" to pkg,
                                "label" to info.loadLabel(activity.packageManager).toString()
                            )
                        }.distinctBy { it["package"] }
                            .sortedBy { it["label"]?.lowercase() }
                        result.success(entries)
                    }
                    "status" -> result.success(mapOf(
                        "stage" to SystemVpnService.stage,
                        "detail" to SystemVpnService.detail
                    ))
                    "stop" -> {
                        waitingConfig = null
                        waitingRouting = null
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
                        val policy = try {
                            VpnRoutingPolicy(
                                call.argument<String>("mode") ?: "all",
                                call.argument<List<String>>("packages") ?: emptyList(),
                                activity.packageName
                            )
                        } catch (e: IllegalArgumentException) {
                            result.error("BAD_APPS", e.message, null)
                            return@setMethodCallHandler
                        }
                        try {
                            val approval = VpnService.prepare(activity)
                            if (approval != null) {
                                waitingConfig = config
                                waitingRouting = policy
                                SystemVpnService.stage = "consent"
                                SystemVpnService.detail = "Waiting for Android VPN permission"
                                @Suppress("DEPRECATION")
                                activity.startActivityForResult(approval, REQUEST_VPN)
                                result.success("permission_requested")
                            } else {
                                launch(activity, config, policy)
                                result.success("starting")
                            }
                        } catch (e: Exception) {
                            waitingConfig = null
                            waitingRouting = null
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
        val policy = waitingRouting
        waitingConfig = null
        waitingRouting = null
        if (resultCode == Activity.RESULT_OK && config != null && policy != null) {
            try {
                launch(activity, config, policy)
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

    private fun launch(activity: Activity, config: String, policy: VpnRoutingPolicy) {
        val intent = Intent(activity, SystemVpnService::class.java)
            .putExtra(SystemVpnService.EXTRA_CONFIG, config)
            .putExtra(SystemVpnService.EXTRA_ROUTING_MODE, policy.mode)
            .putStringArrayListExtra(SystemVpnService.EXTRA_PACKAGES, ArrayList(policy.packages))
        SystemVpnService.stage = "starting"
        SystemVpnService.detail = "Starting Android VPN service"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }
}

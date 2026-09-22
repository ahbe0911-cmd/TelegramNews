package ir.channel.telegram_news

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.net.TrafficStats
import android.provider.Settings
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

    private fun launcherActivities(activity: Activity):
        List<android.content.pm.ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        return activity.packageManager.queryIntentActivities(intent, 0)
    }

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Device app-UID counters: approximate app traffic, NOT
                    // a fabricated tunnel throughput or server speed test.
                    "networkCounters" -> {
                        val uid = android.os.Process.myUid()
                        val received = TrafficStats.getUidRxBytes(uid)
                        val sent = TrafficStats.getUidTxBytes(uid)
                        result.success(mapOf(
                            "rx" to received,
                            "tx" to sent
                        ))
                    }
                    "openVpnSettings" -> {
                        try {
                            activity.startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("NO_VPN_SETTINGS",
                                "Android VPN settings could not open", null)
                        }
                    }
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
                    "openShortcutApp" -> {
                        val pkg = call.argument<String>("package")
                        val component = call.argument<String>("component")
                        if (pkg.isNullOrBlank()) {
                            result.error("SHORTCUT_UNAVAILABLE", "Missing Android package", null)
                        } else {
                            try {
                                val pm = activity.packageManager
                                // The package-only launcher API may return null on
                                // Android 11+ even when the launcher picker can see
                                // an activity. Re-resolve the MAIN/LAUNCHER component
                                // selected by the user and launch that exact alias.
                                val entries = launcherActivities(activity)
                                    .filter { it.activityInfo.packageName == pkg }
                                val selected = entries.firstOrNull {
                                    it.activityInfo.name == component
                                } ?: entries.firstOrNull()
                                val launch = if (selected != null) {
                                    Intent.makeMainActivity(
                                        android.content.ComponentName(
                                            selected.activityInfo.packageName,
                                            selected.activityInfo.name
                                        )
                                    )
                                } else {
                                    pm.getLaunchIntentForPackage(pkg)
                                }
                                if (launch == null) {
                                    result.error("SHORTCUT_UNAVAILABLE",
                                        "No launchable Android activity found for $pkg", null)
                                } else {
                                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    activity.startActivity(launch)
                                    result.success(null)
                                }
                            } catch (error: Exception) {
                                result.error("SHORTCUT_LAUNCH_FAILED",
                                    "Android could not open $pkg: " +
                                        error.javaClass.simpleName, null)
                            }
                        }
                    }
                    "openShortcutWeb" -> {
                        val raw = call.argument<String>("url")
                        val address = try {
                            android.net.Uri.parse(raw)
                        } catch (_: Exception) { null }
                        if (address?.scheme != "https" ||
                            address.host.isNullOrBlank() ||
                            !address.userInfo.isNullOrEmpty()) {
                            result.error("UNSAFE_SHORTCUT", "Only HTTPS links are supported", null)
                        } else {
                            try {
                                val title = call.argument<String>("title") ?: "وب"
                                activity.startActivity(
                                    Intent(activity, GozarWebActivity::class.java)
                                        .putExtra(GozarWebActivity.EXTRA_URL, raw)
                                        .putExtra(GozarWebActivity.EXTRA_TITLE, title.take(48))
                                )
                                result.success(null)
                            } catch (_: Exception) {
                                result.error("WEB_SHORTCUT_FAILED",
                                    "Cannot open the in-app browser", null)
                            }
                        }
                    }
                    "appIcon" -> {
                        val pkg = call.argument<String>("package")
                        val component = call.argument<String>("component")
                        try {
                            if (pkg.isNullOrBlank()) {
                                result.success(null)
                            } else {
                                // Use the visible launcher activity's own icon:
                                // aliases may have a different icon from the
                                // package icon, and package icon lookup can be
                                // restricted by Android package visibility.
                                val pm = activity.packageManager
                                val launcher = launcherActivities(activity)
                                    .firstOrNull { it.activityInfo.packageName == pkg &&
                                        (component.isNullOrEmpty() ||
                                         it.activityInfo.name == component) }
                                val drawable = launcher?.loadIcon(pm)
                                    ?: pm.getApplicationIcon(pkg)
                                val bitmap = android.graphics.Bitmap.createBitmap(
                                    80, 80, android.graphics.Bitmap.Config.ARGB_8888)
                                val canvas = android.graphics.Canvas(bitmap)
                                drawable.setBounds(0, 0, 80, 80)
                                drawable.draw(canvas)
                                val bytes = java.io.ByteArrayOutputStream()
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,
                                    100, bytes)
                                result.success(bytes.toByteArray())
                                bitmap.recycle()
                                bytes.close()
                            }
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    "installedApps" -> {
                        // Retain the actual activity name instead of discarding
                        // distinct launch aliases within the same package.
                        val entries = launcherActivities(activity)
                            .mapNotNull { info ->
                                val pkg = info.activityInfo.packageName
                                if (pkg == activity.packageName) null else mapOf(
                                    "package" to pkg,
                                    "component" to info.activityInfo.name,
                                    "label" to info.loadLabel(
                                        activity.packageManager).toString()
                                )
                            }.distinctBy { it["package"] + "/" + it["component"] }
                             .sortedBy { it["label"]?.lowercase() }
                        result.success(entries)
                    }
                    "measureConnection" -> {
                        // The core measures an outbound request through its
                        // selected proxy, never through the VPN app's direct UID.
                        SystemVpnService.measureActiveConnection { delay ->
                            activity.runOnUiThread {
                                result.success(mapOf(
                                    "ok" to (delay != null),
                                    "latencyMs" to delay
                                ))
                            }
                        }
                    }
                    "status" -> result.success(mapOf(
                        "stage" to SystemVpnService.stage,
                        "detail" to SystemVpnService.detail
                    ))
                    "stop" -> {
                        // Cancel an outstanding Android permission request too.
                        waitingConfig = null
                        waitingRouting = null
                        try {
                            // stopService() only schedules onDestroy(): send an
                            // ordered command to close the TUN immediately.
                            activity.startService(
                                Intent(activity, SystemVpnService::class.java)
                                    .setAction(SystemVpnService.ACTION_STOP)
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            // On restricted Android builds still request normal
                            // service teardown, and report failure if that fails.
                            val stopped = activity.stopService(
                                Intent(activity, SystemVpnService::class.java)
                            )
                            if (stopped) result.success(null) else
                                result.error("VPN_STOP_FAILED",
                                    "Android could not stop the VPN service", null)
                        }
                    }
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrBlank() || config.length > 1024 * 1024) {
                            result.error("INVALID_CONFIG", "Invalid Xray JSON", null)
                            return@setMethodCallHandler
                        }
                        if (SystemVpnService.stage == "running" ||
                            SystemVpnService.stage == "starting" ||
                            SystemVpnService.stage == "stopping" ||
                            SystemVpnService.stage == "consent") {
                            result.error("VPN_BUSY",
                                "Wait for the current VPN operation to finish", null)
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

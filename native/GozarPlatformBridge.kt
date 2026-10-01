package ir.channel.telegram_news

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.SystemClock
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Android helpers for Gozar's launcher and private HTTPS browser.
 * Package visibility is intentionally broad so the user can add every
 * launchable application installed on the device.
 */
object GozarPlatformBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/gozar_platform"
    private const val CACHE_MS = 30000L

    @Volatile private var cachedApps: List<Map<String, String>>? = null
    @Volatile private var cachedAt: Long = 0L

    @Suppress("DEPRECATION")
    private fun installedApplications(
        packageManager: PackageManager
    ): List<ApplicationInfo> =
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            packageManager.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(0L)
            )
        } else {
            packageManager.getInstalledApplications(0)
        }

    @Suppress("DEPRECATION")
    private fun launcherActivities(
        packageManager: PackageManager
    ): List<android.content.pm.ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        return if (android.os.Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(
                    PackageManager.MATCH_ALL.toLong()
                )
            )
        } else {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.MATCH_ALL
            )
        }
    }

    private fun allLaunchableApps(
        activity: MainActivity,
        force: Boolean = false
    ): List<Map<String, String>> {
        val now = SystemClock.elapsedRealtime()
        val existing = cachedApps
        if (!force && existing != null && now - cachedAt < CACHE_MS) {
            return existing
        }

        val pm = activity.packageManager
        val merged = LinkedHashMap<String, Map<String, String>>()

        // Primary source: every activity Android itself exposes to a launcher.
        // This catches apps whose package-level launch intent is not exposed
        // reliably (Instagram and several vendor apps can fall into this case).
        for (info in launcherActivities(pm)) {
            val activityInfo = info.activityInfo ?: continue
            val pkg = activityInfo.packageName ?: continue
            if (pkg == activity.packageName) continue

            val label = try {
                info.loadLabel(pm).toString().trim()
            } catch (_: Throwable) {
                pkg
            }
            merged[pkg] = mapOf(
                "package" to pkg,
                "component" to activityInfo.name,
                "label" to (if (label.isEmpty()) pkg else label)
            )
        }

        // Secondary source: installed packages with a normal launch intent.
        // It fills gaps left by OEM launchers and unusual aliases.
        for (info in installedApplications(pm)) {
            val pkg = info.packageName ?: continue
            if (pkg == activity.packageName || merged.containsKey(pkg)) {
                continue
            }
            val launch = try {
                pm.getLaunchIntentForPackage(pkg)
            } catch (_: Throwable) {
                null
            } ?: continue

            val label = try {
                pm.getApplicationLabel(info).toString().trim()
            } catch (_: Throwable) {
                pkg
            }
            merged[pkg] = mapOf(
                "package" to pkg,
                "component" to (launch.component?.className ?: ""),
                "label" to (if (label.isEmpty()) pkg else label)
            )
        }

        val apps = merged.values
            .sortedBy { (it["label"] ?: "").lowercase() }

        cachedApps = apps
        cachedAt = now
        return apps
    }

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openShortcutApp" -> {
                        val pkg = call.argument<String>("package")
                        val component = call.argument<String>("component")
                        if (pkg.isNullOrBlank()) {
                            result.error(
                                "SHORTCUT_UNAVAILABLE",
                                "Missing Android package",
                                null
                            )
                        } else {
                            try {
                                val pm = activity.packageManager
                                val launchers = mutableListOf<Intent>()

                                if (!component.isNullOrBlank()) {
                                    launchers += Intent(Intent.ACTION_MAIN)
                                        .addCategory(Intent.CATEGORY_LAUNCHER)
                                        .setComponent(
                                            ComponentName(pkg, component)
                                        )
                                }

                                pm.getLaunchIntentForPackage(pkg)?.let {
                                    launchers += it
                                }

                                var opened = false
                                var lastError: Exception? = null
                                for (launch in launchers) {
                                    try {
                                        launch.addFlags(
                                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                                        )
                                        activity.startActivity(launch)
                                        opened = true
                                        break
                                    } catch (error: Exception) {
                                        lastError = error
                                    }
                                }

                                if (opened) {
                                    result.success(null)
                                } else {
                                    result.error(
                                        "SHORTCUT_UNAVAILABLE",
                                        "No working launcher for $pkg" +
                                            (lastError?.let {
                                                ": " + it.javaClass.simpleName
                                            } ?: ""),
                                        null
                                    )
                                }
                            } catch (error: Exception) {
                                result.error(
                                    "SHORTCUT_LAUNCH_FAILED",
                                    "Android could not open $pkg: " +
                                        error.javaClass.simpleName,
                                    null
                                )
                            }
                        }
                    }

                    "openShortcutWeb" -> {
                        val raw = call.argument<String>("url")
                        val address = try {
                            Uri.parse(raw)
                        } catch (_: Exception) {
                            null
                        }

                        if (address?.scheme != "https" ||
                            address.host.isNullOrBlank() ||
                            !address.userInfo.isNullOrEmpty()
                        ) {
                            result.error(
                                "UNSAFE_SHORTCUT",
                                "Only HTTPS links are supported",
                                null
                            )
                        } else {
                            try {
                                val title =
                                    call.argument<String>("title") ?: "وب"
                                activity.startActivity(
                                    Intent(
                                        activity,
                                        GozarWebActivity::class.java
                                    )
                                        .putExtra(
                                            GozarWebActivity.EXTRA_URL,
                                            raw
                                        )
                                        .putExtra(
                                            GozarWebActivity.EXTRA_TITLE,
                                            title.take(48)
                                        )
                                )
                                result.success(null)
                            } catch (_: Exception) {
                                result.error(
                                    "WEB_SHORTCUT_FAILED",
                                    "Cannot open the in-app browser",
                                    null
                                )
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
                                val pm = activity.packageManager
                                val drawable =
                                    if (component.isNullOrEmpty()) {
                                        pm.getApplicationIcon(pkg)
                                    } else {
                                        try {
                                            pm.getActivityIcon(
                                                ComponentName(
                                                    pkg,
                                                    component
                                                )
                                            )
                                        } catch (_: PackageManager.NameNotFoundException) {
                                            pm.getApplicationIcon(pkg)
                                        }
                                    }

                                val bitmap = Bitmap.createBitmap(
                                    96,
                                    96,
                                    Bitmap.Config.ARGB_8888
                                )
                                val canvas = Canvas(bitmap)
                                // Slight overscan compensates for the safe-zone
                                // padding used by many adaptive app icons.
                                val overscan = 5
                                drawable.setBounds(
                                    -overscan,
                                    -overscan,
                                    96 + overscan,
                                    96 + overscan
                                )
                                drawable.draw(canvas)

                                val bytes = ByteArrayOutputStream()
                                bitmap.compress(
                                    Bitmap.CompressFormat.PNG,
                                    100,
                                    bytes
                                )
                                result.success(bytes.toByteArray())
                                bitmap.recycle()
                                bytes.close()
                            }
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }

                    "installedApps" -> {
                        val force =
                            call.argument<Boolean>("force") ?: false
                        Thread({
                            try {
                                val apps =
                                    allLaunchableApps(activity, force)
                                activity.runOnUiThread {
                                    result.success(apps)
                                }
                            } catch (error: Throwable) {
                                activity.runOnUiThread {
                                    result.error(
                                        "APP_LIST_FAILED",
                                        error.javaClass.simpleName,
                                        null
                                    )
                                }
                            }
                        }, "rosha-installed-apps").start()
                    }

                    else -> result.notImplemented()
                }
            }
    }
}

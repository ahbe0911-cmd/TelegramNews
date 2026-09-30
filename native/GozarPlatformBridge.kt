package ir.channel.telegram_news

import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Android helpers for Gozar's launcher and private HTTPS browser.
 * No VPN service, tunnel engine, proxy, or network-routing code lives here.
 */
object GozarPlatformBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/gozar_platform"

    private fun launcherActivities(activity: MainActivity):
        List<android.content.pm.ResolveInfo> {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        return activity.packageManager.queryIntentActivities(intent, 0)
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
                                val entries = launcherActivities(activity)
                                    .filter { it.activityInfo.packageName == pkg }
                                val selected = entries.firstOrNull {
                                    it.activityInfo.name == component
                                } ?: entries.firstOrNull()
                                val launchers = mutableListOf<Intent>()
                                if (selected != null) {
                                    launchers += Intent(Intent.ACTION_MAIN)
                                        .addCategory(Intent.CATEGORY_LAUNCHER)
                                        .setClassName(
                                            selected.activityInfo.packageName,
                                            selected.activityInfo.name
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
                                    Intent(activity, GozarWebActivity::class.java)
                                        .putExtra(GozarWebActivity.EXTRA_URL, raw)
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
                                val drawable = if (component.isNullOrEmpty()) {
                                    pm.getApplicationIcon(pkg)
                                } else {
                                    try {
                                        pm.getActivityIcon(
                                            ComponentName(pkg, component)
                                        )
                                    } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                                        pm.getApplicationIcon(pkg)
                                    }
                                }
                                val bitmap = Bitmap.createBitmap(
                                    80, 80, Bitmap.Config.ARGB_8888
                                )
                                val canvas = Canvas(bitmap)
                                drawable.setBounds(0, 0, 80, 80)
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
                        val entries = launcherActivities(activity)
                            .mapNotNull { info ->
                                val pkg = info.activityInfo.packageName
                                if (pkg == activity.packageName) {
                                    null
                                } else {
                                    mapOf(
                                        "package" to pkg,
                                        "component" to info.activityInfo.name,
                                        "label" to info.loadLabel(
                                            activity.packageManager
                                        ).toString()
                                    )
                                }
                            }
                            .distinctBy {
                                it["package"] + "/" + it["component"]
                            }
                            .sortedBy { it["label"]?.lowercase() }
                        result.success(entries)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}

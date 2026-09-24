package ir.channel.telegram_news

import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Invoked only by the combined Gozar + Forkgram APK.
 * The Telegram destination is the REAL native Forkgram LaunchActivity subclass
 * packaged with Gozar, not an external package or a WebView.
 */
object GozarForkgramBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/forkgram"
    private const val TARGET_TAB = "gozar_target_tab"
    private var channel: MethodChannel? = null
    private var pendingTab: Int? = null

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        val initialTab = activity.intent.getIntExtra(TARGET_TAB, -1)
        if (initialTab in 0..4 && initialTab != 1) pendingTab = initialTab
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "showForkgram" -> {
                    try {
                        // Explicit component in THIS package. No launcher intent,
                        // browser URL, second APK or package auto-installation.
                        val telegram = Intent().setClassName(
                            activity.packageName,
                            "ir.channel.telegram_news.GozarTelegramActivity")
                            .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        if (activity.packageManager.resolveActivity(telegram, 0) == null) {
                            result.error("FORKGRAM_MISSING",
                                "Native Forkgram activity is not packaged", null)
                        } else {
                            activity.startActivity(telegram)
                            result.success(null)
                        }
                    } catch (_: ActivityNotFoundException) {
                        result.error("FORKGRAM_MISSING",
                            "Native Forkgram activity cannot be launched", null)
                    } catch (_: SecurityException) {
                        result.error("FORKGRAM_UNAVAILABLE",
                            "Native Forkgram activity is inaccessible", null)
                    } catch (_: Exception) {
                        result.error("FORKGRAM_FAILED",
                            "Native Forkgram startup failed", null)
                    }
                }
                "takePendingTab" -> {
                    result.success(pendingTab)
                    pendingTab = null
                    activity.intent.removeExtra(TARGET_TAB)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onNewIntent(intent: Intent) {
        val tab = intent.getIntExtra(TARGET_TAB, -1)
        if (tab !in 0..4 || tab == 1) return
        pendingTab = tab
        channel?.invokeMethod("navigate", mapOf("tab" to tab))
    }
}

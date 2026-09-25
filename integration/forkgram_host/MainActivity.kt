package ir.channel.telegram_news

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.telegram.ui.LaunchActivity

/**
 * EXPERIMENTAL source for the future ONE-APK build; currently NOT compiled.
 *
 * Forkgram remains the real Android Activity and runs its regular navigation,
 * media and messaging engine. A single cached FlutterView renders all Gozar
 * tabs above it. For the Telegram tab the Flutter view is reduced to the
 * bottom navigation bar, exposing Forkgram's real content in the same Activity.
 *
 * This class MUST be compiled into the Forkgram Android application together
 * with the actual Flutter AOT bundle, all native Gozar bridge classes, the
 * merged manifests and a combined Application implementation. Shipping only
 * this file or the upstream APK does not create an integrated application.
 */
class MainActivity : LaunchActivity() {
    private var gozarEngine: FlutterEngine? = null
    private var gozarView: FlutterView? = null
    private var hostContent: FrameLayout? = null
    private var showingForkgram = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val content = findViewById<FrameLayout>(android.R.id.content) ?: return
        hostContent = content
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(this)
        loader.ensureInitializationComplete(this, null)
        val engine = FlutterEngine(this)
        gozarEngine = engine
        // The production host copies and registers the real VPN and reminders.
        SystemVpnBridge.attach(this, engine)
        GozarReminderBridge.attach(this, engine)
        val view = FlutterView(this)
        gozarView = view
        content.addView(view, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.BOTTOM
        ))
        view.attachToFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "ir.channel.telegram_tdnews/forkgram")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showForkgram" -> {
                        resizeGozarOverlay(true)
                        result.success(null)
                    }
                    "showGozar" -> {
                        resizeGozarOverlay(false)
                        result.success(null)
                    }
                    "takePendingTab" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "main")
        )
        if (intent?.getBooleanExtra("gozar_open_notes", false) == true) {
            resizeGozarOverlay(false)
            GozarReminderBridge.onNewIntent(intent)
        }
    }

    private fun resizeGozarOverlay(nativeTelegram: Boolean) {
        val view = gozarView ?: return
        if (hostContent == null) return
        showingForkgram = nativeTelegram
        val height = if (nativeTelegram) {
            // Sized to Flutter NavigationBar. Flutter renders index 1 with no
            // header or placeholder; the underlying native Activity is visible.
            (68f * resources.displayMetrics.density + 0.5f).toInt()
        } else ViewGroup.LayoutParams.MATCH_PARENT
        view.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, height, Gravity.BOTTOM)
        view.requestLayout()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        SystemVpnBridge.onActivityResult(this, requestCode, resultCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        GozarReminderBridge.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("gozar_open_notes", false)) resizeGozarOverlay(false)
        GozarReminderBridge.onNewIntent(intent)
    }

    override fun onDestroy() {
        gozarView?.detachFromFlutterEngine()
        gozarView = null
        gozarEngine?.destroy()
        gozarEngine = null
        hostContent = null
        super.onDestroy()
    }
}

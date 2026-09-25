package ir.channel.telegram_news

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * ONLY the official Telegram Web K browser, not an MTProto client, login
 * interceptor or Telegram SDK. The original standalone Gozar VPN and routing
 * stay untouched. Like other in-app Gozar browsers, Gozar's own UID bypasses
 * its VPN tunnel to prevent recursive tunnelling. Use the external browser
 * button when the phone browser should follow Android's VPN routing.
 */
class GozarTelegramWebViewFactory(
    private val activity: Activity,
    messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    companion object {
        const val VIEW_TYPE = "ir.channel.telegram_news/gozar_telegram_web"
        const val CONTROLS = "ir.channel.telegram_tdnews/gozar_telegram_controls"
        const val EVENTS = "ir.channel.telegram_tdnews/gozar_telegram_events"
        const val OFFICIAL_URL = "https://web.telegram.org/k/"
    }

    private val events = MethodChannel(messenger, EVENTS)
    private var activePage: TelegramView? = null
    private var tabActive = false

    val controls = MethodChannel(messenger, CONTROLS).also { channel ->
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    tabActive = call.argument<Boolean>("active") == true
                    activePage?.setActive(tabActive)
                    result.success(null)
                }
                "reload" -> {
                    activePage?.reload()
                    result.success(null)
                }
                "openExternal" -> {
                    try {
                        activity.startActivity(Intent(Intent.ACTION_VIEW,
                            Uri.parse(OFFICIAL_URL))
                            .addCategory(Intent.CATEGORY_BROWSABLE))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("NO_BROWSER", "No browser is available", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun create(context: android.content.Context, viewId: Int,
                        args: Any?): PlatformView {
        val page = TelegramView(context, activity, events) { closed ->
            if (activePage === closed) activePage = null
        }
        activePage = page
        page.setActive(tabActive)
        return page
    }

    private class TelegramView(
        context: android.content.Context,
        private val activity: Activity,
        private val events: MethodChannel,
        private val onDispose: (TelegramView) -> Unit,
    ) : PlatformView {
        private val frame = FrameLayout(context)
        private val web = WebView(context)
        private val progress = ProgressBar(context, null,
            android.R.attr.progressBarStyleHorizontal)
        private var started = SystemClock.elapsedRealtime()
        private var paused = false
        private var mainFrameFailed = false

        init {
            frame.addView(web, FrameLayout.LayoutParams(-1, -1))
            progress.max = 100
            val dp = context.resources.displayMetrics.density
            frame.addView(progress, FrameLayout.LayoutParams(-1, (3 * dp).toInt()))
            web.setBackgroundColor(Color.WHITE)
            web.settings.apply {
                javaScriptEnabled = true  // Telegram's own web client requires JS
                domStorageEnabled = true  // retain Telegram's own login session
                useWideViewPort = true
                loadWithOverviewMode = true
                textZoom = 100
                allowFileAccess = false
                allowContentAccess = false
                setSupportMultipleWindows(false)
                javaScriptCanOpenWindowsAutomatically = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                cacheMode = WebSettings.LOAD_DEFAULT
                mediaPlaybackRequiresUserGesture = true
                // NO arbitrary JavaScript injection, WebView JS bridge or
                // user-agent spoofing. Telegram selects its own responsive UI.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    safeBrowsingEnabled = true
                }
            }
            CookieManager.getInstance().setAcceptCookie(true)
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView, request: WebResourceRequest
                ): Boolean {
                    if (!request.isForMainFrame) return false
                    val url = request.url
                    if (url.scheme == "https" && url.host == "web.telegram.org") {
                        return false
                    }
                    // Keep unrelated sites OUTSIDE the authenticated Telegram
                    // browser, and refuse file://, http:// and intent://.
                    if (url.scheme == "https") {
                        try {
                            activity.startActivity(Intent(Intent.ACTION_VIEW, url)
                                .addCategory(Intent.CATEGORY_BROWSABLE))
                        } catch (_: Exception) {
                            events.invokeMethod("error", null)
                        }
                    }
                    return true
                }

                override fun onPageStarted(
                    view: WebView, url: String?, favicon: android.graphics.Bitmap?
                ) {
                    started = SystemClock.elapsedRealtime()
                    mainFrameFailed = false
                    progress.visibility = View.VISIBLE
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    progress.visibility = View.GONE
                    if (!mainFrameFailed) {
                        events.invokeMethod("loaded", mapOf(
                            "durationMs" to (SystemClock.elapsedRealtime() - started)))
                    }
                }

                override fun onReceivedHttpError(
                    view: WebView, request: WebResourceRequest,
                    response: WebResourceResponse
                ) {
                    if (request.isForMainFrame && response.statusCode >= 400) {
                        mainFrameFailed = true
                        events.invokeMethod("error", null)
                    }
                }

                override fun onReceivedError(
                    view: WebView, request: WebResourceRequest,
                    error: android.webkit.WebResourceError
                ) {
                    if (request.isForMainFrame) {
                        mainFrameFailed = true
                        events.invokeMethod("error", null)
                    }
                }
            }
            web.webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView, newProgress: Int) {
                    progress.progress = newProgress
                    progress.visibility =
                        if (newProgress >= 100) View.GONE else View.VISIBLE
                }
            }
            web.loadUrl(OFFICIAL_URL)
        }

        fun setActive(active: Boolean) {
            if (!active && !paused) {
                web.onPause()
                paused = true
            } else if (active && paused) {
                web.onResume()
                paused = false
            }
        }

        fun reload() = web.reload()

        override fun getView(): View = frame

        override fun dispose() {
            onDispose(this)
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            frame.removeView(web)
            web.destroy()
        }
    }
}

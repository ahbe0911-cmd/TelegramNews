package ir.channel.telegram_news

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Four trusted HTTPS web messenger pages inside the standalone Gozar host.
 * No TDLib, phone contacts, account access, injected JavaScript, or VPN changes.
 *
 * The WebViews belong to Gozar's UID. That UID is excluded from its own VPN
 * tunnel to avoid traffic recursion. A separate "open in phone browser"
 * action uses the browser's own UID when routing through a VPN is needed.
 */
class GozarSocialWebViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    companion object {
        const val VIEW_TYPE = "ir.channel.telegram_news/gozar_social_web"
        const val CONTROLS = "ir.channel.telegram_tdnews/gozar_social_controls"
        const val EVENTS = "ir.channel.telegram_tdnews/gozar_social_events"

        val sites = listOf(
            "https://web.telegram.org/a/",
            "https://web.bale.ai/",
            "https://web.rubika.ir/",
            "https://web.eitaa.com/"
        )
    }

    private val views = mutableSetOf<SocialPlatformView>()
    private val events = MethodChannel(messenger, EVENTS)
    private var currentIndex = -1

    val controls = MethodChannel(messenger, CONTROLS).also { channel ->
        channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "setActive" -> {
                    val next = call.argument<Int>("index") ?: -1
                    currentIndex = if (next in sites.indices) next else -1
                    views.toList().forEach { it.updateActive(currentIndex) }
                    result.success(null)
                }
                "reload" -> {
                    val index = call.argument<Int>("index") ?: -1
                    views.firstOrNull { it.index == index }?.reload()
                    result.success(null)
                }
                "openExternal" -> {
                    val index = call.argument<Int>("index") ?: -1
                    if (index !in sites.indices) {
                        result.error("INVALID_SITE", "Unknown messenger", null)
                    } else {
                        try {
                            activity.startActivity(Intent(Intent.ACTION_VIEW,
                                Uri.parse(sites[index])).addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("NO_BROWSER", "No browser is available", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val index = (args as? Map<*, *>)?.get("index") as? Int ?: -1
        require(index in sites.indices) { "Unknown Gozar social web page" }
        val page = SocialPlatformView(context, index, events) { closed ->
            views.remove(closed)
        }
        views.add(page)
        page.updateActive(currentIndex)
        return page
    }

    private class SocialPlatformView(
        context: Context,
        val index: Int,
        private val events: MethodChannel,
        private val onDisposed: (SocialPlatformView) -> Unit,
    ) : PlatformView {
        private val frame = FrameLayout(context)
        private val web = WebView(context)
        private val progress = ProgressBar(context, null,
            android.R.attr.progressBarStyleHorizontal)
        private var loadStarted = SystemClock.elapsedRealtime()
        private var paused = false

        init {
            frame.addView(web, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT))
            progress.max = 100
            val progressHeight = (3 * context.resources.displayMetrics.density + .5f).toInt()
            frame.addView(progress, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, progressHeight))
            web.setBackgroundColor(android.graphics.Color.WHITE)
            web.settings.javaScriptEnabled = true
            web.settings.domStorageEnabled = true
            // Respect each messenger's responsive viewport meta tag. Android
            // defaults can otherwise render the desktop-width page clipped
            // horizontally on a narrow phone (notably the Bale web layout).
            web.settings.useWideViewPort = true
            web.settings.loadWithOverviewMode = true
            web.settings.textZoom = 100
            web.setInitialScale(0)
            web.settings.allowFileAccess = false
            web.settings.allowContentAccess = false
            web.settings.setSupportMultipleWindows(false)
            web.settings.javaScriptCanOpenWindowsAutomatically = false
            web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            web.settings.cacheMode = WebSettings.LOAD_DEFAULT
            web.settings.mediaPlaybackRequiresUserGesture = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                web.settings.safeBrowsingEnabled = true
            }
            CookieManager.getInstance().setAcceptCookie(true)
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView, request: WebResourceRequest
                ): Boolean {
                    // A messenger's HTTPS navigation is allowed. Never launch
                    // intent://, file://, HTTP, javascript: or local content.
                    return request.url.scheme != "https"
                }

                override fun onPageStarted(
                    view: WebView, url: String?, favicon: android.graphics.Bitmap?
                ) {
                    loadStarted = SystemClock.elapsedRealtime()
                    progress.visibility = View.VISIBLE
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    progress.visibility = View.GONE
                    events.invokeMethod("pageFinished", mapOf(
                        "index" to index,
                        "loadMs" to (SystemClock.elapsedRealtime() - loadStarted)
                    ))
                }

                override fun onReceivedError(
                    view: WebView, request: WebResourceRequest,
                    error: android.webkit.WebResourceError
                ) {
                    if (request.isForMainFrame) {
                        events.invokeMethod("pageError", mapOf(
                            "index" to index
                        ))
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
            web.loadUrl(sites[index])
        }

        fun updateActive(activeIndex: Int) {
            val shouldPause = activeIndex != index
            if (shouldPause && !paused) {
                web.onPause()
                paused = true
            } else if (!shouldPause && paused) {
                web.onResume()
                paused = false
            }
        }

        fun reload() {
            web.reload()
        }

        override fun getView(): View = frame

        override fun dispose() {
            onDisposed(this)
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            frame.removeView(web)
            web.destroy()
        }
    }
}

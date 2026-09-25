package ir.channel.telegram_news

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import java.io.ByteArrayInputStream
import org.json.JSONObject
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebResourceResponse
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
 * Three native WebViews alongside the existing Telegram WebView.
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
        const val SHAD_ALTERNATE = "https://web.shad.ir/"
        private const val FONT_PATH = "/.gozar-assets/vazirmatn-regular.ttf"
        private const val FONT_ASSET = "flutter_assets/assets/fonts/Vazirmatn-Regular.ttf"
        private val trustedFontHosts = setOf(
            "web.rubika.ir", "my.shad.ir", "web.shad.ir", "web.eitaa.com"
        )

        val sites = listOf(
            "https://web.rubika.ir/",
            "https://my.shad.ir/",
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
                "alternateShad" -> {
                    val index = call.argument<Int>("index") ?: -1
                    if (index == 1) {
                        views.firstOrNull { it.index == index }?.alternateShad()
                    }
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
        val page = SocialPlatformView(context, activity, index, events) { closed ->
            views.remove(closed)
        }
        views.add(page)
        page.updateActive(currentIndex)
        return page
    }

    private class SocialPlatformView(
        context: Context,
        private val activity: Activity,
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
        private var pageFailed = false
        private var everActivated = false
        private var fontAppliedToPage = false
        private val downloads = GozarSocialDownloads(activity, web, index, events)
        // An explicit long-press Save action also works for images which the
        // website displays without providing a download button.
        private fun installImageSave() {
            web.setOnLongClickListener {
                val hit = web.hitTestResult
                val source = hit.extra
                val type = hit.type
                val isImage = type == WebView.HitTestResult.IMAGE_TYPE ||
                    type == WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE
                val scheme = if (source == null) null else
                    Uri.parse(source).scheme?.lowercase()
                if (!isImage || source.isNullOrBlank() ||
                    (scheme != "https" && scheme != "blob")) {
                    false
                } else {
                    AlertDialog.Builder(activity)
                        .setTitle("ذخیرهٔ تصویر")
                        .setNegativeButton("انصراف", null)
                        .setPositiveButton("ذخیره در گالری") { _, _ ->
                            downloads.saveUserDownload(source,
                                web.settings.userAgentString, null, null)
                        }.show()
                    true
                }
            }
        }

        // Load the licensed font from a virtual same-origin URL. A short CSS
        // rule avoids base64-encoding a large TTF into JavaScript on the UI thread.
        private fun applyGozarFont(pageUrl: String?) {
            if (fontAppliedToPage || pageUrl.isNullOrBlank()) return
            val uri = try { Uri.parse(pageUrl) } catch (_: Exception) { return }
            val host = uri.host?.lowercase() ?: return
            if (uri.scheme != "https" || host !in trustedFontHosts) return
            fontAppliedToPage = true
            val css = """
                @font-face {
                    font-family: 'GozarVazirmatn';
                    src: url('https://$host$FONT_PATH') format('truetype');
                    font-weight: 400;
                    font-style: normal;
                }
                body, input, textarea, button, [contenteditable='true'] {
                    font-family: 'GozarVazirmatn', sans-serif !important;
                }
            """.trimIndent()
            web.evaluateJavascript("""
                (function () {
                    if (document.getElementById('gozar-local-font')) return;
                    if (!document.head) return;
                    var style = document.createElement('style');
                    style.id = 'gozar-local-font';
                    style.textContent = ${JSONObject.quote(css)};
                    document.head.appendChild(style);
                })();
            """.trimIndent(), null)
        }

        init {
            installImageSave()
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
            // Do not pre-rasterize inactive heavyweight pages in GPU memory.
            web.settings.setSupportZoom(false)
            if (index == 1) {
                // Shad sign-in may need third-party cookies and a browser UA.
                CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)
                web.settings.userAgentString = web.settings.userAgentString
                    .replace("; wv", "").replace("Version/4.0 ", "")
            }
            web.settings.mediaPlaybackRequiresUserGesture = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                web.settings.safeBrowsingEnabled = true
            }
            CookieManager.getInstance().setAcceptCookie(true)
            web.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView, request: WebResourceRequest
                ): WebResourceResponse? {
                    val url = request.url
                    if (url.scheme == "https" &&
                        url.host?.lowercase() in trustedFontHosts &&
                        url.path == FONT_PATH) {
                        return try {
                            WebResourceResponse("font/ttf", null,
                                activity.assets.open(FONT_ASSET))
                        } catch (_: Exception) {
                            // Never fetch the virtual resource from the network.
                            WebResourceResponse("text/plain", "UTF-8",
                                ByteArrayInputStream(ByteArray(0)))
                        }
                    }
                    return super.shouldInterceptRequest(view, request)
                }

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
                    pageFailed = false
                    fontAppliedToPage = false
                    progress.visibility = View.VISIBLE
                    // Avoid timed fallback navigation that used to replace
                    // Shad's page abruptly while a user was interacting.
                }

                override fun onPageCommitVisible(view: WebView, url: String?) {
                    applyGozarFont(url)
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    applyGozarFont(url)
                    progress.visibility = View.GONE
                    if (pageFailed) return
                    events.invokeMethod("pageFinished", mapOf(
                        "index" to index,
                        "loadMs" to (SystemClock.elapsedRealtime() - loadStarted)
                    ))
                }

                override fun onReceivedHttpError(
                    view: WebView, request: WebResourceRequest,
                    response: WebResourceResponse
                ) {
                    if (request.isForMainFrame && response.statusCode >= 400) {
                        pageFailed = true
                        events.invokeMethod("pageError", mapOf("index" to index))
                    }
                }

                override fun onReceivedError(
                    view: WebView, request: WebResourceRequest,
                    error: android.webkit.WebResourceError
                ) {
                    if (request.isForMainFrame) {
                        pageFailed = true
                        events.invokeMethod("pageError", mapOf("index" to index))
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

        fun alternateShad() {
            if (index != 1) return
            web.loadUrl(SHAD_ALTERNATE)
        }

        fun updateActive(activeIndex: Int) {
            if (activeIndex == index) everActivated = true
            val shouldPause = activeIndex != index
            if (shouldPause && !paused && everActivated) {
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
            downloads.dispose()
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            frame.removeView(web)
            web.destroy()
        }
    }
}

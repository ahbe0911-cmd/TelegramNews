package ir.channel.telegram_news

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import org.json.JSONObject
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
    private var prewarmedPage: TelegramView? = null
    private var tabActive = false

    // Warm the actual Telegram WebView after Gozar's home is visible.
    // Reuse it on the first tab visit to avoid another cold page navigation.
    init {
        Handler(Looper.getMainLooper()).postDelayed({
            if (activePage == null && prewarmedPage == null &&
                !activity.isFinishing && !activity.isDestroyed) {
                prewarmedPage = makePage(activity)
            }
        }, 1200)
    }

    private fun makePage(context: android.content.Context): TelegramView =
        TelegramView(context, activity, events, ::handleProxyNavigation) { closed ->
            if (activePage === closed) activePage = null
            if (prewarmedPage === closed) prewarmedPage = null
        }

    private fun validatedMtproto(server: String, port: Int, secret: String): Uri? {
        if (!server.matches(Regex("^[A-Za-z0-9.-]{1,253}$")) ||
            port !in 1..65535 ||
            !secret.matches(Regex("(?i)^[0-9a-f]{32,512}$"))) return null
        return Uri.Builder().scheme("tg").authority("proxy")
            .appendQueryParameter("server", server)
            .appendQueryParameter("port", port.toString())
            .appendQueryParameter("secret", secret).build()
    }

    private fun validatedMtprotoLink(uri: Uri): Uri? {
        val fromTelegram = uri.scheme.equals("tg", true) &&
            uri.host.equals("proxy", true)
        val fromWeb = uri.scheme.equals("https", true) &&
            uri.host?.lowercase() in setOf("t.me", "telegram.me") &&
            uri.path?.trimEnd('/') == "/proxy"
        if (!fromTelegram && !fromWeb) return null
        return try {
            val server = uri.getQueryParameter("server")?.trim() ?: return null
            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: return null
            val secret = uri.getQueryParameter("secret")?.trim() ?: return null
            validatedMtproto(server, port, secret)
        } catch (_: Exception) { null }
    }

    private fun launchProxy(uri: Uri): Boolean = try {
        activity.startActivity(Intent(Intent.ACTION_VIEW, uri)
            .addCategory(Intent.CATEGORY_BROWSABLE))
        true
    } catch (_: Exception) { false }

    private fun handleProxyNavigation(uri: Uri): Boolean {
        val isLink = (uri.scheme.equals("tg", true) &&
                uri.host.equals("proxy", true)) ||
            (uri.scheme.equals("https", true) &&
                uri.host?.lowercase() in setOf("t.me", "telegram.me") &&
                uri.path?.trimEnd('/') == "/proxy")
        if (!isLink) return false
        val target = validatedMtprotoLink(uri)
        if (target == null || !launchProxy(target)) {
            events.invokeMethod("proxyLinkError", null)
        }
        return true
    }

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
                "setFontEnabled" -> {
                    activePage?.setFontEnabled(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "openMtprotoInTelegram" -> {
                    val server = call.argument<String>("server")?.trim() ?: ""
                    val port = call.argument<Int>("port") ?: 0
                    val secret = call.argument<String>("secret")?.trim() ?: ""
                    val uri = validatedMtproto(server, port, secret)
                    if (uri == null) {
                        result.error("INVALID_PROXY", "Invalid MTProto proxy fields", null)
                    } else if (!launchProxy(uri)) {
                        result.error("NO_TELEGRAM_APP",
                            "No Telegram app can handle this proxy link", null)
                    } else {
                        result.success(null)
                    }
                }
                "openMtprotoLink" -> {
                    val uri = try {
                        Uri.parse(call.argument<String>("url")?.trim() ?: "")
                    } catch (_: Exception) { Uri.EMPTY }
                    val target = validatedMtprotoLink(uri)
                    if (target == null) {
                        result.error("INVALID_PROXY", "Invalid MTProto proxy link", null)
                    } else if (!launchProxy(target)) {
                        result.error("NO_TELEGRAM_APP",
                            "No Telegram app can handle this proxy link", null)
                    } else {
                        result.success(null)
                    }
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
        val page = prewarmedPage ?: makePage(context)
        prewarmedPage = null
        activePage = page
        page.setActive(tabActive)
        page.reportPreload()
        return page
    }

    private class TelegramView(
        context: android.content.Context,
        private val activity: Activity,
        private val events: MethodChannel,
        private val onProxyNavigation: (Uri) -> Boolean,
        private val onDispose: (TelegramView) -> Unit,
    ) : PlatformView {
        private val frame = FrameLayout(context)
        private val web = WebView(context)
        private val progress = ProgressBar(context, null,
            android.R.attr.progressBarStyleHorizontal)
        private var started = SystemClock.elapsedRealtime()
        private var paused = false
        private var everActivated = false
        private var pageFinished = false
        private var lastLoadMs: Long? = null
        private var mainFrameFailed = false
        private var fontEnabled = true
        // This is the same licensed local font that Gozar uses in Flutter.
        // Lazy initialization avoids delaying Telegram's first navigation.
        private val fontCss: String by lazy {
            val bytes = activity.assets.open(
                "flutter_assets/assets/fonts/Vazirmatn-Regular.ttf").use {
                    it.readBytes()
                }
            val font = Base64.encodeToString(bytes, Base64.NO_WRAP)
            "@font-face{font-family:'GozarVazirmatn';" +
                "src:url(data:font/ttf;base64,$font) format('truetype');" +
                "font-style:normal;font-weight:100 900;}" +
                "body,input,textarea,button,[contenteditable='true']," +
                "[dir='auto']{font-family:'GozarVazirmatn',sans-serif!important;}"
        }
        private val downloads = GozarSocialDownloads(
            activity, web, 0, events)

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
                // Retain Chromium's regular web asset/service-worker cache.
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
                    if (onProxyNavigation(url)) return true
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
                    pageFinished = false
                    lastLoadMs = null
                    mainFrameFailed = false
                    progress.visibility = View.VISIBLE
                }

                override fun onPageFinished(view: WebView, url: String?) {
                    progress.visibility = View.GONE
                    pageFinished = true
                    // Defer expensive font injection until the tab is visited.
                    if (everActivated) applyFontStyle()
                    if (!mainFrameFailed) {
                        lastLoadMs = SystemClock.elapsedRealtime() - started
                        events.invokeMethod("loaded", mapOf(
                            "durationMs" to lastLoadMs))
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

        fun reportPreload() {
            lastLoadMs?.let {
                events.invokeMethod("loaded", mapOf("durationMs" to it))
            }
        }

        fun setActive(active: Boolean) {
            if (active && !everActivated) {
                everActivated = true
                if (pageFinished) applyFontStyle()
            }
            // Do not suspend preloading JavaScript before the first tab visit.
            if (!active && !paused && everActivated) {
                web.onPause()
                paused = true
            } else if (active && paused) {
                web.onResume()
                paused = false
            }
        }

        fun reload() = web.reload()

        fun setFontEnabled(enabled: Boolean) {
            fontEnabled = enabled
            applyFontStyle()
        }

        private fun applyFontStyle() {
            if (web.url?.let { Uri.parse(it).host } != "web.telegram.org") return
            val code = try {
                if (fontEnabled) JSONObject.quote(fontCss) else "null"
            } catch (_: Exception) {
                return // Missing asset: retain Telegram's normal font.
            }
            // A CSS-only, optional visual style: this script never reads
            // page text, credentials, DOM contents or Telegram data.
            web.evaluateJavascript("""
                (function() {
                  var old = document.getElementById('gozar-font-style');
                  if (old) old.remove();
                  var css = $code;
                  if (css && document.head) {
                    var style = document.createElement('style');
                    style.id = 'gozar-font-style';
                    style.textContent = css;
                    document.head.appendChild(style);
                  }
                })();
            """.trimIndent(), null)
        }

        override fun getView(): View = frame

        override fun dispose() {
            onDispose(this)
            downloads.dispose()
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            frame.removeView(web)
            web.destroy()
        }
    }
}

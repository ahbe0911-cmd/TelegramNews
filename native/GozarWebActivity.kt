package ir.channel.telegram_news

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * In-app HTTPS shortcut browser. It runs under Gozar's Android UID, which
 * the VPN app currently excludes from the TUN to avoid core recursion.
 * Showing a web page here does NOT assert that its requests use the VPN.
 */
class GozarWebActivity : Activity() {
    companion object {
        const val EXTRA_URL = "shortcut_url"
        const val EXTRA_TITLE = "shortcut_title"
    }

    private lateinit var web: WebView
    private lateinit var progress: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(5, 13, 34)
        window.navigationBarColor = Color.rgb(5, 13, 34)

        val url = intent.getStringExtra(EXTRA_URL)
        val parsed = try { android.net.Uri.parse(url) } catch (_: Exception) { null }
        if (parsed?.scheme != "https" || parsed.host.isNullOrBlank() ||
            !parsed.userInfo.isNullOrEmpty()) {
            finish()
            return
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(5, 13, 34))
        }
        val toolbar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(6))
        }
        val close = TextView(this).apply {
            text = "‹  گذر"
            textSize = 18f
            setTextColor(Color.rgb(54, 234, 255))
            setPadding(dp(8), dp(10), dp(12), dp(10))
            setOnClickListener { finish() }
        }
        val title = TextView(this).apply {
            text = intent.getStringExtra(EXTRA_TITLE) ?: "مرورگر گذر"
            textSize = 16f
            setSingleLine(true)
            ellipsize = android.text.TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }
        val refresh = TextView(this).apply {
            text = "⟳"
            textSize = 26f
            setTextColor(Color.rgb(54, 234, 255))
            setPadding(dp(13), dp(6), dp(7), dp(6))
            setOnClickListener { web.reload() }
        }
        toolbar.addView(close)
        toolbar.addView(title, LinearLayout.LayoutParams(0, dp(49), 1f))
        toolbar.addView(refresh)
        root.addView(toolbar)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        progress.max = 100
        root.addView(progress, LinearLayout.LayoutParams(-1, dp(3)))

        web = WebView(this)
        web.setBackgroundColor(Color.WHITE)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.allowFileAccess = false
        web.settings.allowContentAccess = false
        web.settings.setSupportMultipleWindows(false)
        web.settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            web.settings.safeBrowsingEnabled = true
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView, request: WebResourceRequest
            ): Boolean {
                val next = request.url
                return next.scheme != "https"
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progress.progress = newProgress
                progress.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
            }
        }
        root.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        if (savedInstanceState != null) web.restoreState(savedInstanceState)
        else web.loadUrl(url!!)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + .5f).toInt()

    override fun onSaveInstanceState(outState: Bundle) {
        web.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        web.stopLoading()
        web.destroy()
        super.onDestroy()
    }
}

package ir.channel.telegram_news

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import dev.minios.tgwsproxy.proxy.ProxyConfig
import dev.minios.tgwsproxy.proxy.TgWsProxyServer
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns a local-only MTProto listener inside this APK. No separate proxy APK,
 * VPN permission, root or paid server is required. Reachability is not guaranteed.
 */
object EmbeddedProxyManager {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mutex = Mutex()
    private var server: TgWsProxyServer? = null
    private var activePort = 0
    private var activeSecret = ""
    private val stopping = AtomicBoolean(false)

    private suspend fun start(context: Context): Map<String, Any> {
        mutex.lock()
        try {
            if (server?.isRunning == true) {
                return mapOf("host" to "127.0.0.1", "port" to activePort,
                    "secret" to ("dd" + activeSecret), "running" to true)
            }
            val prefs = context.getSharedPreferences("embedded_mtproto", Context.MODE_PRIVATE)
            val secret = prefs.getString("secret", null)?.takeIf {
                it.matches(Regex("[0-9a-fA-F]{32}"))
            } ?: ProxyConfig.generateSecret().also {
                prefs.edit().putString("secret", it).apply()
            }
            // Both independently installed brands must not fight over one listener.
            val port = if (context.packageName.endsWith("_cafenet")) 17444 else 17443
            val ready = CompletableDeferred<Unit>()
            val created = TgWsProxyServer(ProxyConfig(
                host = "127.0.0.1", port = port, secret = secret,
                autoOptimizeConnection = true, cfProxyEnabled = true))
            created.onStatusChange = { running ->
                if (running && !ready.isCompleted) ready.complete(Unit)
            }
            server = created
            activePort = port
            activeSecret = secret
            stopping.set(false)
            scope.launch(Dispatchers.IO) {
                try {
                    created.start()
                    if (!ready.isCompleted) {
                        ready.completeExceptionally(IllegalStateException("Proxy stopped before ready"))
                    }
                } catch (failure: Exception) {
                    if (!ready.isCompleted) ready.completeExceptionally(failure)
                }
            }
            try {
                withTimeout(12000L) { ready.await() }
            } catch (failure: Exception) {
                withContext(Dispatchers.IO) { created.stop() }
                if (server === created) server = null
                throw failure
            }
            return mapOf("host" to "127.0.0.1", "port" to port,
                "secret" to ("dd" + secret), "running" to true)
        } finally {
            mutex.unlock()
        }
    }

    private suspend fun stop() {
        mutex.lock()
        try {
            if (stopping.getAndSet(true)) return
            val old = server
            server = null
            if (old != null) withContext(Dispatchers.IO) { old.stop() }
        } finally {
            stopping.set(false)
            mutex.unlock()
        }
    }

    fun attach(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "ir.channel.telegram_tdnews/embedded_proxy").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> scope.launch {
                    try { result.success(start(activity.applicationContext)) }
                    catch (failure: Exception) {
                        result.error("PROXY_START_FAILED",
                            failure.message ?: "Local proxy failed to start", null)
                    }
                }
                "stop" -> scope.launch {
                    try { stop(); result.success(true) }
                    catch (failure: Exception) {
                        result.error("PROXY_STOP_FAILED", "Could not stop local proxy", null)
                    }
                }
                "status" -> result.success(server?.isRunning == true)
                else -> result.notImplemented()
            }
        }
    }
}

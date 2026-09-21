package ir.channel.telegram_news

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A separate PROCESS and SOCKS-ONLY Xray controller for this app's TDLib.
 *
 * The system VPN deliberately excludes its own package from TUN to avoid
 * redirecting its native Xray outbound sockets into the TUN again. Running
 * a second controller in the SAME process would also overwrite the Go
 * xray.tun.fd environment key. This process never receives a TUN fd and only
 * accepts SOCKS on 127.0.0.1:10809.
 */
class InternalTelegramProxyService : Service() {
    companion object {
        const val EXTRA_CONFIG = "telegram_internal_xray_config"
        private const val CHANNEL = "internal_telegram_xray"
        private const val NOTIFICATION_ID = 19742
    }

    private val starting = AtomicBoolean(false)
    @Volatile private var stopping = false
    private var controller: CoreController? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrBlank()) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // No TUN is permitted in this process. Never accept an arbitrary
        // platform VPN config as a replacement for a SOCKS-only config.
        try {
            val inbounds = JSONObject(config).getJSONArray("inbounds")
            require(inbounds.length() == 1 &&
                inbounds.getJSONObject(0).getString("protocol") == "socks" &&
                inbounds.getJSONObject(0).getString("listen") == "127.0.0.1" &&
                inbounds.getJSONObject(0).getInt("port") == 10809)
        } catch (_: Exception) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        startForegroundNotification()
        if (!starting.compareAndSet(false, true)) return START_NOT_STICKY
        stopping = false
        Thread({
            try {
                Seq.setContext(applicationContext)
                Libv2ray.initCoreEnv(filesDir.absolutePath, "")
                val core = Libv2ray.newCoreController(object : CoreCallbackHandler {
                    override fun startup(): Long = 0
                    override fun shutdown(): Long = 0
                    override fun onEmitStatus(code: Long, message: String?): Long = 0
                })
                controller = core
                // tunFd=0: the internal core never modifies platform VPN TUN.
                core.startLoop(config, 0)
                if (stopping) core.stopLoop()
            } catch (_: Throwable) {
                stopSelf()
            }
        }, "telegram-socks-xray").start()
        return START_NOT_STICKY
    }

    private fun startForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL, "اتصال داخلی تلگرام", NotificationManager.IMPORTANCE_LOW
            ))
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notice = builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("اتصال داخلی تلگرام")
            .setContentText("موتور مستقل Xray مخصوص کافی‌نت و نبض خبر")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notice,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notice)
        }
    }

    override fun onDestroy() {
        stopping = true
        val current = controller
        controller = null
        Thread({
            try { current?.stopLoop() } catch (_: Throwable) {}
        }, "stop-telegram-socks-xray").start()
        super.onDestroy()
    }
}

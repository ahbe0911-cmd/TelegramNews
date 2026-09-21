package ir.channel.telegram_news

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray

/**
 * Android's TUN descriptor is passed to Xray. Stop requests are handled by
 * the service itself, rather than waiting for Android to call onDestroy().
 */
class SystemVpnService : VpnService() {
    companion object {
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_ROUTING_MODE = "vpn_routing_mode"
        const val EXTRA_PACKAGES = "vpn_routing_packages"
        const val ACTION_STOP = "ir.channel.telegram_news.ACTION_STOP_VPN"
        @Volatile var stage = "off"
        @Volatile var detail = "VPN خاموش است."
        private const val NOTIFICATION_CHANNEL = "xray_device_vpn"
        private const val NOTIFICATION_ID = 19741
    }

    private val resourceLock = Any()
    @Volatile private var stopping = false
    private var tunnel: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private var startupThread: Thread? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopVpn("Disconnect requested")
            stopSelf()
            return START_NOT_STICKY
        }
        if (stopping) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Android may redeliver a start while the same service is running.
        if (startupThread != null) return START_NOT_STICKY
        val config = intent?.getStringExtra(EXTRA_CONFIG)
        val routing = try {
            VpnRoutingPolicy(
                intent?.getStringExtra(EXTRA_ROUTING_MODE) ?: "all",
                intent?.getStringArrayListExtra(EXTRA_PACKAGES) ?: emptyList(),
                packageName
            )
        } catch (e: IllegalArgumentException) {
            stage = "error"
            detail = "Invalid VPN app selection"
            stopSelf()
            return START_NOT_STICKY
        }
        if (config.isNullOrBlank() || VpnService.prepare(this) != null) {
            stage = "error"
            detail = "Android VPN permission or configuration missing"
            stopSelf()
            return START_NOT_STICKY
        }
        createForegroundNotification()
        stage = "starting"
        detail = "Initializing Xray-core and Android TUN"
        startupThread = Thread({
            try {
                Seq.setContext(applicationContext)
                Libv2ray.initCoreEnv(filesDir.absolutePath, "")
                if (stopping) return@Thread
                val builder = Builder()
                    .setSession(applicationInfo.loadLabel(packageManager).toString())
                    .setMtu(1500)
                    .addAddress("10.25.0.2", 30)
                    .addRoute("0.0.0.0", 0)
                    .addAddress("fd10:25::2", 126)
                    .addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("2606:4700:4700::1111")
                if (routing.mode == "selected") {
                    routing.packages.forEach { pkg ->
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                            throw IllegalStateException("Selected app missing: $pkg", e)
                        }
                    }
                } else {
                    builder.addDisallowedApplication(packageName)
                }
                val fd = builder.establish()
                    ?: throw IllegalStateException("Android did not establish TUN")
                synchronized(resourceLock) {
                    if (stopping) {
                        fd.close()
                        return@Thread
                    }
                    tunnel = fd
                }
                val controller = Libv2ray.newCoreController(object : CoreCallbackHandler {
                    override fun startup(): Long = 0
                    override fun shutdown(): Long = 0
                    override fun onEmitStatus(code: Long, message: String?): Long = 0
                })
                synchronized(resourceLock) {
                    if (stopping) return@Thread
                    core = controller
                }
                // stopVpn() closes the fd immediately and calls stopLoop() on
                // another thread, even when startLoop() has not returned yet.
                controller.startLoop(config, fd.fd)
                synchronized(resourceLock) {
                    if (!stopping) {
                        stage = "running"
                        detail = "Xray TUN active; test the actual server separately"
                    }
                }
            } catch (error: Throwable) {
                if (!stopping) {
                    stage = "error"
                    detail = "Xray core failed: " + error.javaClass.simpleName
                    stopSelf()
                }
            }
        }, "gozar-vpn-start").also { it.start() }
        return START_NOT_STICKY
    }

    /**
     * Closing the TUN immediately drops Android's VPN interface. The Xray
     * controller is stopped off the main thread before reporting "off".
     * This is also used for revocation and unexpected service destruction.
     */
    private fun stopVpn(reason: String) {
        val startup: Thread?
        synchronized(resourceLock) {
            if (stopping) return
            stopping = true
            stage = "stopping"
            detail = reason
            startup = startupThread
            try { tunnel?.close() } catch (_: Exception) { }
            tunnel = null
        }
        Thread({
            try {
                // Start may still be publishing its controller; wait briefly,
                // then stopLoop() can interrupt a still-blocking startLoop().
                startup?.join(500)
                val active = synchronized(resourceLock) {
                    val value = core
                    core = null
                    value
                }
                try { active?.stopLoop() } catch (_: Throwable) { }
                // If startLoop returned after stopLoop raced with startup,
                // startup's stopped check prevents a stale "running" state.
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } finally {
                stage = "off"
                detail = "VPN خاموش است."
            }
        }, "gozar-vpn-stop").start()
    }

    private fun createForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                NOTIFICATION_CHANNEL, "VPN اتصال سراسری",
                NotificationManager.IMPORTANCE_LOW
            ))
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("VPN سراسری")
            .setContentText("اتصال شبکه توسط Xray در حال اجرا است")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onRevoke() {
        stopVpn("Android revoked the VPN permission")
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn("Android VPN service destroyed")
        super.onDestroy()
    }
}

package ir.channel.telegram_news

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray

/**
 * Xray-core's TUN inbound receives the actual Android VpnService file
 * descriptor. This package is excluded from platform VPN routing to prevent
 * Xray's own outbound sockets from looping; the app's TDLib connects to the
 * core's local SOCKS listener when VPN is activated.
 */
class SystemVpnService : VpnService() {
    companion object {
        const val EXTRA_CONFIG = "xray_config"
        const val EXTRA_ROUTING_MODE = "vpn_routing_mode"
        const val EXTRA_PACKAGES = "vpn_routing_packages"
        @Volatile var stage = "off"
        @Volatile var detail = "VPN خاموش است."
        private const val NOTIFICATION_CHANNEL = "xray_device_vpn"
        private const val NOTIFICATION_ID = 19741
    }

    @Volatile private var stopped = false
    private var tunnel: ParcelFileDescriptor? = null
    private var core: CoreController? = null

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
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
        Thread {
            try {
                Seq.setContext(applicationContext)
                Libv2ray.initCoreEnv(filesDir.absolutePath, "")
                val builder = Builder()
                    .setSession(applicationInfo.loadLabel(packageManager).toString())
                    .setMtu(1500)
                    .addAddress("10.25.0.2", 30)
                    .addRoute("0.0.0.0", 0)
                    .addAddress("fd10:25::2", 126)
                    .addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("2606:4700:4700::1111")
                // Android allows EITHER an allow-list OR a deny-list.
                // Our own package never enters TUN to protect Xray outbound
                // sockets; its TDLib uses the local SOCKS inbound instead.
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
                if (stopped) {
                    fd.close()
                    return@Thread
                }
                tunnel = fd
                val controller = Libv2ray.newCoreController(object : CoreCallbackHandler {
                    override fun startup(): Long = 0
                    override fun shutdown(): Long = 0
                    override fun onEmitStatus(code: Long, message: String?): Long = 0
                })
                core = controller
                controller.startLoop(config, fd.fd)
                if (stopped) {
                    controller.stopLoop()
                    return@Thread
                }
                stage = "running"
                detail = "Xray TUN active; test the actual server separately"
            } catch (error: Throwable) {
                stage = "error"
                detail = "Xray core failed: " + error.javaClass.simpleName
                stopSelf()
            }
        }.start()
        return START_NOT_STICKY
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
        stage = "off"
        detail = "Android revoked the VPN permission"
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopped = true
        val active = core
        core = null
        try { tunnel?.close() } catch (_: Exception) { }
        tunnel = null
        Thread {
            try { active?.stopLoop() } catch (_: Throwable) { }
        }.start()
        if (stage != "error") {
            stage = "off"
            detail = "VPN خاموش است."
        }
        super.onDestroy()
    }
}

package ir.channel.telegram_news

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Device-local, one-shot alarms. Note text stays in Flutter preferences; only
 * a short title + trigger time are kept for Android reboot recovery.
 */
object GozarReminderScheduler {
    private const val STORE = "gozar_reminder_alarms_v1"
    private const val CHANNEL = "gozar_note_reminders"
    private val safeId = Regex("^[a-zA-Z0-9_-]{1,60}$")

    private fun alarms(context: Context): android.content.SharedPreferences =
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE)

    private fun pending(context: Context, id: String): PendingIntent {
        val intent = Intent(context, GozarReminderReceiver::class.java)
            .setAction("ir.channel.telegram_news.NOTE_REMINDER")
            .setData(Uri.parse("gozar://note/" + Uri.encode(id)))
            .putExtra("id", id)
        return PendingIntent.getBroadcast(context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun notificationsAllowed(context: Context): Boolean {
        val notificationManager = context.getSystemService(
            Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 24 &&
            !notificationManager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }

    fun exactAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return manager.canScheduleExactAlarms()
    }

    fun schedule(context: Context, id: String, title: String, time: Long): String {
        require(safeId.matches(id)) { "Invalid reminder identifier" }
        require(title.isNotBlank() && title.length <= 80) { "Invalid title" }
        require(time > System.currentTimeMillis()) { "Reminder must be in the future" }
        require(notificationsAllowed(context)) { "Notifications are disabled" }
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val alarm = pending(context, id)
        manager.cancel(alarm)
        val exact = exactAllowed(context)
        if (Build.VERSION.SDK_INT >= 23) {
            if (exact) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, time, alarm)
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, time, alarm)
            }
        } else if (Build.VERSION.SDK_INT >= 19) {
            manager.setExact(AlarmManager.RTC_WAKEUP, time, alarm)
        } else {
            manager.set(AlarmManager.RTC_WAKEUP, time, alarm)
        }
        // Commit before returning: a boot receiver can recreate every alarm.
        alarms(context).edit().putString(id, JSONObject()
            .put("title", title).put("at", time).toString()).commit()
        return if (exact) "exact" else "approximate"
    }

    fun cancel(context: Context, id: String) {
        if (!safeId.matches(id)) return
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .cancel(pending(context, id))
        alarms(context).edit().remove(id).apply()
    }

    fun fire(context: Context, id: String) {
        if (!safeId.matches(id)) return
        val raw = alarms(context).getString(id, null) ?: return
        val record = try { JSONObject(raw) } catch (_: Exception) { return }
        val time = record.optLong("at", 0L)
        if (time <= 0L || time > System.currentTimeMillis() + 60_000) return
        // Remove first to prevent a second broadcast from duplicating an alarm.
        alarms(context).edit().remove(id).commit()
        if (!notificationsAllowed(context)) return
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL, "یادآور یادداشت‌های گذر",
                NotificationManager.IMPORTANCE_HIGH).apply {
                description = "اعلان یادآوری یادداشت‌هایی که خودتان زمان‌بندی کرده‌اید"
                enableVibration(true)
            })
        }
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("gozar_open_notes", true)
        val tap = PendingIntent.getActivity(context, id.hashCode(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("یادآوری گذر")
            .setContentText(record.optString("title", "یادداشت"))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setShowWhen(true)
            .setWhen(time)
            .build()
        manager.notify("gozar_note_" + id, 1, notification)
    }

    fun recover(context: Context) {
        val saved = alarms(context).all
        for ((id, raw) in saved) {
            if (raw !is String || !safeId.matches(id)) continue
            val record = try { JSONObject(raw) } catch (_: Exception) { null }
            val time = record?.optLong("at", 0L) ?: 0L
            val title = record?.optString("title", "") ?: ""
            if (time <= System.currentTimeMillis() || title.isBlank()) {
                cancel(context, id)
                continue
            }
            if (notificationsAllowed(context)) {
                try { schedule(context, id, title, time) } catch (_: Exception) {}
            }
        }
    }
}

class GozarReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "ir.channel.telegram_news.NOTE_REMINDER") {
            val id = intent.getStringExtra("id") ?: return
            GozarReminderScheduler.fire(context, id)
        }
    }
}

class GozarReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED ->
                GozarReminderScheduler.recover(context)
        }
    }
}

/** Permission consent and app navigation, available only in standalone Gozar. */
object GozarReminderBridge {
    private const val CHANNEL = "ir.channel.telegram_tdnews/reminders"
    private const val NOTIFICATION_REQUEST = 6851
    private var waitingPermission: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    fun attach(activity: MainActivity, engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "notificationsGranted" ->
                    result.success(GozarReminderScheduler.notificationsAllowed(activity))
                "requestNotifications" -> {
                    if (GozarReminderScheduler.notificationsAllowed(activity)) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= 33 &&
                        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED) {
                        if (waitingPermission != null) {
                            result.error("BUSY", "Notification permission dialog is active", null)
                        } else {
                            waitingPermission = result
                            activity.requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_REQUEST)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "exactAlarmsAllowed" ->
                    result.success(GozarReminderScheduler.exactAllowed(activity))
                "openExactAlarmSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 31) {
                            activity.startActivity(Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:" + activity.packageName)))
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("SETTINGS_UNAVAILABLE",
                            "Cannot open exact alarm settings", null)
                    }
                }
                "schedule" -> {
                    val id = call.argument<String>("id")
                    val title = call.argument<String>("title")
                    val time = call.argument<Long>("atMillis")
                    if (id.isNullOrBlank() || title.isNullOrBlank() || time == null) {
                        result.error("INVALID_REMINDER", "Missing reminder fields", null)
                    } else {
                        try {
                            result.success(GozarReminderScheduler.schedule(
                                activity, id, title, time))
                        } catch (error: Exception) {
                            result.error("REMINDER_FAILED",
                                error.message ?: "Alarm scheduling failed", null)
                        }
                    }
                }
                "cancel" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("INVALID_REMINDER", "Missing reminder id", null)
                    } else {
                        GozarReminderScheduler.cancel(activity, id)
                        result.success(null)
                    }
                }
                "takeOpenedReminder" -> {
                    val opened = activity.intent
                        ?.getBooleanExtra("gozar_open_notes", false) ?: false
                    activity.intent?.removeExtra("gozar_open_notes")
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_REQUEST) return false
        waitingPermission?.success(grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED)
        waitingPermission = null
        return true
    }

    fun onNewIntent(intent: Intent) {
        if (intent.getBooleanExtra("gozar_open_notes", false)) {
            channel?.invokeMethod("openNotes", null)
        }
    }
}

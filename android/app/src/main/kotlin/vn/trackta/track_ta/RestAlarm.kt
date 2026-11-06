package vn.trackta.track_ta

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

object RestAlarm {
    private const val preferences = "trackta_rest_alarm"
    private const val deadlineKey = "deadline_millis"
    private const val channelId = "rest_done_v2"
    private const val notificationId = 9101
    private const val requestCode = 9101

    private fun manager(context: Context): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun notifications(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun pendingAlarm(context: Context): PendingIntent {
        val intent = Intent(context, RestAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun canScheduleExactly(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager(context).canScheduleExactAlarms()

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val service = notifications(context)
        if (!service.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = service.getNotificationChannel(channelId)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun deadline(context: Context): Long {
        val saved = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .getLong(deadlineKey, 0L)
        return if (saved > System.currentTimeMillis()) saved else 0L
    }

    fun start(context: Context, seconds: Int): Long {
        createChannel(context)
        manager(context).cancel(pendingAlarm(context))
        notifications(context).cancel(notificationId)
        val deadline = System.currentTimeMillis() + seconds * 1000L
        val prefs = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
        prefs.edit().putLong(deadlineKey, deadline).commit()
        try {
            manager(context).setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                deadline,
                pendingAlarm(context)
            )
        } catch (e: SecurityException) {
            prefs.edit().remove(deadlineKey).apply()
            throw e
        }
        return deadline
    }

    fun cancel(context: Context) {
        manager(context).cancel(pendingAlarm(context))
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .edit().remove(deadlineKey).apply()
        notifications(context).cancel(notificationId)
    }

    fun onFinished(context: Context) {
        val prefs = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
        val saved = prefs.getLong(deadlineKey, 0L)
        if (saved == 0L || saved > System.currentTimeMillis() + 1000L) return
        prefs.edit().remove(deadlineKey).apply()
        if (!canNotify(context)) return
        createChannel(context)
        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
                .setSound(soundUri(context))
                .setVibrate(longArrayOf(0, 400, 160, 400))
                .setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Hết giờ nghỉ")
            .setContentText("Sẵn sàng cho hiệp tiếp theo")
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        notifications(context).notify(notificationId, notification)
    }

    fun restoreAfterBoot(context: Context) {
        val saved = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .getLong(deadlineKey, 0L)
        if (saved <= System.currentTimeMillis()) {
            context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                .edit().remove(deadlineKey).apply()
            return
        }
        if (canScheduleExactly(context) && canNotify(context)) {
            manager(context).setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                saved,
                pendingAlarm(context)
            )
        }
    }

    // Resource name stays valid when resource IDs are reassigned by later APKs.
    private fun soundUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/rest_bell")

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            channelId,
            "Đồng hồ nghỉ",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Chuông và rung khi hết giờ nghỉ giữa hiệp"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 160, 400)
            setSound(
                soundUri(context),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        notifications(context).createNotificationChannel(channel)
    }
}

class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RestAlarm.onFinished(context)
    }
}

class RestBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            RestAlarm.restoreAfterBoot(context)
        }
    }
}

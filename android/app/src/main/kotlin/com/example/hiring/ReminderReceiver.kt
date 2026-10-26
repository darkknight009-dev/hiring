package com.example.hiring

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/// Fires periodic "check if they accepted" reminders while a connection
/// request is marked as awaiting acceptance.
class ReminderReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_REMINDERS = "hiring_radar_reminders"
        const val EXTRA_KEY = "key"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val ACTION_SHOW_REMINDER = "app.hiringradar.SHOW_REMINDER"
        private const val PREFS_NAME = "feed_radar_reminders"
        private const val ENTRY_PREFIX = "entry:"

        fun schedule(
            context: Context,
            key: String,
            title: String,
            body: String,
            intervalMillis: Long,
        ) {
            val safeInterval = intervalMillis.coerceAtLeast(60_000L)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val entry = JSONObject()
                .put("title", title)
                .put("body", body)
                .put("interval", safeInterval)
                .toString()
            prefs.edit().putString(ENTRY_PREFIX + key, entry).apply()
            scheduleAlarm(context, key, title, body, safeInterval)
        }

        fun cancel(context: Context, key: String) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
            if (alarmManager is android.app.AlarmManager) {
                alarmManager.cancel(pendingIntent(context, key, "", ""))
            }
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().remove(ENTRY_PREFIX + key).apply()
        }

        fun restoreAll(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            for ((storedKey, raw) in prefs.all) {
                if (!storedKey.startsWith(ENTRY_PREFIX) || raw !is String) continue
                try {
                    val key = storedKey.removePrefix(ENTRY_PREFIX)
                    val entry = JSONObject(raw)
                    scheduleAlarm(
                        context,
                        key,
                        entry.optString("title", "FeedRadar"),
                        entry.optString("body", ""),
                        entry.optLong("interval", 12L * 60 * 60 * 1000),
                    )
                } catch (_: Exception) {
                    prefs.edit().remove(storedKey).apply()
                }
            }
        }

        private fun pendingIntent(
            context: Context,
            key: String,
            title: String,
            body: String,
        ): PendingIntent {
            val intent = Intent(context, ReminderReceiver::class.java).apply {
                action = ACTION_SHOW_REMINDER
                putExtra(EXTRA_KEY, key.hashCode())
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            return PendingIntent.getBroadcast(
                context,
                key.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun scheduleAlarm(
            context: Context,
            key: String,
            title: String,
            body: String,
            intervalMillis: Long,
        ) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val firstAt = SystemClock.elapsedRealtime() + intervalMillis
            manager.setInexactRepeating(
                android.app.AlarmManager.ELAPSED_REALTIME,
                firstAt,
                intervalMillis,
                pendingIntent(context, key, title, body),
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            restoreAll(context)
            return
        }
        if (intent.action != ACTION_SHOW_REMINDER) return
        val key = intent.getIntExtra(EXTRA_KEY, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "FeedRadar"
        val body = intent.getStringExtra(EXTRA_BODY) ?: return
        showNotification(context, key, title, body)
    }

    private fun showNotification(context: Context, id: Int, title: String, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_REMINDERS,
                    "Follow-up reminders",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Reminders to check connection replies" }
            )
        }
        val openApp = PendingIntent.getActivity(
            context,
            id,
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_REMINDERS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()
        manager.notify(id, notification)
    }
}

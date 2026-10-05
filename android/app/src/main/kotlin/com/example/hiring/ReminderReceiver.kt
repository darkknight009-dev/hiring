package com.example.hiring

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/// Fires periodic "check if they accepted" reminders while a connection
/// request is marked as awaiting acceptance.
class ReminderReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_REMINDERS = "hiring_radar_reminders"
        const val EXTRA_KEY = "key"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val ACTION_SHOW_REMINDER = "app.hiringradar.SHOW_REMINDER"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_SHOW_REMINDER) return
        val key = intent.getIntExtra(EXTRA_KEY, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Hiring Radar"
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

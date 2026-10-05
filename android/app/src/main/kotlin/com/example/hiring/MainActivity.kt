package com.example.hiring

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingShared: Map<String, String?>? = null
    private lateinit var shareChannel: MethodChannel

    companion object {
        const val CHANNEL = "app.hiringradar/share"
        const val CHANNEL_CAPTURES = "hiring_radar_captures"
        private const val REQUEST_NOTIFICATIONS = 4101
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchSharing" -> {
                    result.success(pendingShared)
                    pendingShared = null
                }
                "isRadarEnabled" -> result.success(isRadarEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "showNotification" -> {
                    val args = call.arguments as? Map<*, *>
                    showCaptureNotification(
                        (args?.get("title") as? String) ?: "FeedRadar",
                        (args?.get("body") as? String) ?: "",
                        (args?.get("id") as? Number)?.toInt() ?: 1001
                    )
                    result.success(null)
                }
                "scheduleReminder" -> {
                    val args = call.arguments as? Map<*, *>
                    scheduleReminder(
                        key = (args?.get("key") as? String) ?: "reminder",
                        title = (args?.get("title") as? String) ?: "FeedRadar",
                        body = (args?.get("body") as? String) ?: "",
                        intervalMillis = (args?.get("intervalMillis") as? Number)?.toLong()
                            ?: 12L * 60 * 60 * 1000
                    )
                    result.success(null)
                }
                "cancelReminder" -> {
                    val args = call.arguments as? Map<*, *>
                    cancelReminder((args?.get("key") as? String) ?: "reminder")
                    result.success(null)
                }
                "updateRadarKeywords" -> {
                    val args = call.arguments as? Map<*, *>
                    val keywords = (args?.get("keywords") as? List<*>)
                        ?.filterIsInstance<String>()
                        .orEmpty()
                    RadarAccessibilityService.userKeywords = keywords
                    result.success(null)
                }
                "openEmail" -> {
                    val args = call.arguments as? Map<*, *>
                    openEmail(
                        to = (args?.get("to") as? String) ?: "",
                        subject = (args?.get("subject") as? String) ?: "",
                        body = (args?.get("body") as? String) ?: "",
                        attachmentPath = args?.get("attachmentPath") as? String
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Bridge radar captures from the accessibility service to Flutter.
        RadarAccessibilityService.onPostCaptured = { payload ->
            runOnUiThread {
                shareChannel.invokeMethod("onRadarPost", payload)
            }
        }
        createNotificationChannel()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureIntent(intent)
    }

    // ---- share intake (ACTION_SEND / PROCESS_TEXT) -------------------------

    private fun captureIntent(intent: Intent?) {
        if (intent == null) return
        val shared: Map<String, String?>? = when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                val title = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                if (text.isNullOrEmpty() && title.isNullOrEmpty()) null
                else mapOf("text" to text, "title" to title, "url" to null)
            }
            Intent.ACTION_PROCESS_TEXT -> {
                val text = intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)
                if (text.isNullOrEmpty()) null
                else mapOf("text" to text, "title" to null, "url" to null)
            }
            else -> null
        }
        if (shared == null) return
        if (!::shareChannel.isInitialized) {
            pendingShared = shared
            return
        }
        shareChannel.invokeMethod("onSharedPost", shared, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {
                pendingShared = shared
            }
        })
    }

    // ---- radar status -------------------------------------------------------

    private fun isRadarEnabled(): Boolean {
        val expected = ComponentName(this, RadarAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            val component = ComponentName.unflattenFromString(splitter.next())
            if (component != null && component == expected) return true
        }
        return false
    }

    // ---- notifications ------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_CAPTURES,
                    "Captured opportunities",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "New hiring posts captured by the radar" }
            )
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
            }
        }
    }

    private fun showCaptureNotification(title: String, body: String, id: Int) {
        if (body.isEmpty()) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openApp = PendingIntent.getActivity(
            this,
            id,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_CAPTURES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()
        manager.notify(id, notification)
    }

    // ---- reminders ----------------------------------------------------------

    private fun reminderPendingIntent(key: String, title: String, body: String): PendingIntent {
        val intent = Intent(this, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_SHOW_REMINDER
            putExtra(ReminderReceiver.EXTRA_KEY, key.hashCode())
            putExtra(ReminderReceiver.EXTRA_TITLE, title)
            putExtra(ReminderReceiver.EXTRA_BODY, body)
        }
        return PendingIntent.getBroadcast(
            this,
            key.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun scheduleReminder(key: String, title: String, body: String, intervalMillis: Long) {
        val manager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = reminderPendingIntent(key, title, body)
        val firstAt = SystemClock.elapsedRealtime() + intervalMillis
        manager.setInexactRepeating(AlarmManager.ELAPSED_REALTIME, firstAt, intervalMillis, pending)
    }

    private fun cancelReminder(key: String) {
        val manager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(reminderPendingIntent(key, "", ""))
    }

    // ---- email handoff ------------------------------------------------------

    private fun openEmail(to: String, subject: String, body: String, attachmentPath: String?) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${Uri.encode(to)}"))
        intent.putExtra(Intent.EXTRA_SUBJECT, subject)
        intent.putExtra(Intent.EXTRA_TEXT, body)
        if (!attachmentPath.isNullOrEmpty()) {
            val file = File(attachmentPath)
            if (file.exists()) {
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                intent.putExtra(Intent.EXTRA_STREAM, uri)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        try {
            startActivity(Intent.createChooser(intent, "Send email"))
        } catch (_: Exception) {
            // No email client installed; the draft stays copyable in the app.
        }
    }
}

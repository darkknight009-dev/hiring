package com.example.hiring

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat

/**
 * Passive feed scanner. Reads visible text nodes in the LinkedIn app while the
 * user scrolls, applies a local keyword gate, and forwards candidate posts to
 * Flutter over the app.hiringradar/share channel. It NEVER clicks, types,
 * focuses, or sends anything: read-only observation.
 *
 * It also owns a low-priority ongoing status notification that updates in
 * realtime while the user scrolls: posts seen, first-filter passes and — via
 * [applyFlutterStats] — second-filter, AI, and save counters from Flutter.
 */
class RadarAccessibilityService : AccessibilityService() {

    companion object {
        const val LINKEDIN_PACKAGE = "com.linkedin.android"
        const val MIN_POST_CHARS = 60
        const val MAX_POST_CHARS = 4000
        const val CHANNEL_STATUS = "hiring_radar_status"
        const val STATUS_NOTIFICATION_ID = 1002
        private const val MIN_EVENT_INTERVAL_MS = 1500L
        private const val MAX_NODES = 600
        private const val MAX_DEPTH = 40
        private const val MAX_PENDING_POSTS = 20
        private const val MAX_OBSERVED_HASHES = 2000

        /// Set by MainActivity once the Flutter engine is ready; null while no
        /// engine is listening (app swiped away), so posts are buffered instead
        /// of vanishing.
        @Volatile
        var listener: ((Map<String, String?>) -> Unit)? = null
            private set

        @Volatile
        var isEnabled: Boolean = false

        /// User's job-preference keywords, pushed from Flutter. A post matching
        /// any of these passes the gate even without a generic hiring keyword.
        @Volatile
        var userKeywords: List<String> = emptyList()

        // ---- live status statistics (session-scoped, shown in the shade) ----

        /// Distinct post-sized text blocks observed on screen.
        @Volatile
        var observedPosts = 0
            private set

        /// Distinct posts that passed the first (keyword) filter and were sent
        /// to Flutter.
        @Volatile
        var gatePassedPosts = 0
            private set

        /// Second-filter / AI / save counters reported by Flutter.
        @Volatile
        var flutterStats: Map<String, Int> = emptyMap()

        @Volatile
        var filterMode: String = "score"

        /// Posts captured while no engine was listening wait here and are
        /// flushed on the next [attach].
        private val pendingPayloads = ArrayDeque<Map<String, String?>>()

        /// The live service instance, used to refresh the status notification
        /// from static context (method channel calls, Flutter stats).
        @Volatile
        private var instance: RadarAccessibilityService? = null

        /// Registers the Flutter listener and flushes anything buffered while
        /// no engine was attached.
        fun attach(newListener: ((Map<String, String?>) -> Unit)?) {
            listener = newListener
            if (newListener != null) {
                while (true) {
                    val payload = synchronized(pendingPayloads) {
                        pendingPayloads.removeFirstOrNull()
                    } ?: break
                    try {
                        newListener(payload)
                    } catch (_: Exception) {
                        // Never crash on Dart-side issues.
                    }
                }
            }
            instance?.refreshStatus()
        }

        /// Called from the method channel with the Flutter-side counters
        /// (second filter, AI verdicts, saves) so the status notification
        /// reflects the whole pipeline in realtime.
        fun applyFlutterStats(stats: Map<String, Int>, mode: String) {
            flutterStats = stats
            filterMode = mode
            instance?.refreshStatus()
        }
    }

    private var lastEmitElapsedMs = 0L
    private val seenHashes = LinkedHashSet<Int>()
    private val observedHashes = LinkedHashSet<Int>()

    private val keywordGate = listOf(
        "hiring", "join our team", "join the team", "we are hiring", "we're hiring",
        "open role", "open position", "job opening", "looking for a", "looking for an",
        "apply now", "apply here", "send your resume", "dm me", "comment interested",
        "vacancy", "vacancies", "careers", "recruiting", "recruiter", "job alert",
        "immediate joiner", "walk-in", "walk in interview", "freelance opportunity"
    )

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.DEFAULT
            notificationTimeout = 500
            packageNames = arrayOf(LINKEDIN_PACKAGE)
        }
        isEnabled = true
        // "Capturing is ON" — posted the moment the service is enabled.
        refreshStatus()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        android.util.Log.d(
            "FeedRadar",
            "event type=${event.eventType} pkg=${event.packageName}"
        )
        val root: AccessibilityNodeInfo = rootInActiveWindow ?: run {
            android.util.Log.d("FeedRadar", "rootInActiveWindow is null")
            return
        }
        if (root.packageName?.toString() != LINKEDIN_PACKAGE) {
            android.util.Log.d("FeedRadar", "wrong package: ${root.packageName}")
            return
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastEmitElapsedMs < MIN_EVENT_INTERVAL_MS) return
        lastEmitElapsedMs = now

        val texts = ArrayList<String>()
        collectTexts(root, texts, 0)
        root.recycleCompat()
        android.util.Log.d("FeedRadar", "collected ${texts.size} texts")
        if (texts.isEmpty()) return

        // Heuristic: the longest visible text blocks are post bodies.
        val candidates = texts
            .filter { it.length in MIN_POST_CHARS..MAX_POST_CHARS }
            .sortedByDescending { it.length }
            .take(4)

        // Heuristic author: a short person-like line near the top of the feed.
        val author = texts.firstOrNull {
            it.length in 2..40 && !it.contains("http") && it.none { c -> c.isDigit() }
        }

        for (text in candidates) {
            // Count distinct posts viewed this session (first filter input).
            rememberObserved(text.hashCode())

            val lower = text.lowercase()
            val matched = keywordGate.any { lower.contains(it) } ||
                userKeywords.any { kw -> kw.isNotBlank() && lower.contains(kw.lowercase()) }
            if (!matched) continue
            val hash = text.hashCode()
            if (!seenHashes.add(hash)) continue
            if (seenHashes.size > 300) {
                val iterator = seenHashes.iterator()
                repeat(100) { if (iterator.hasNext()) { iterator.next(); iterator.remove() } }
            }
            gatePassedPosts++
            val payload = mapOf(
                "text" to text,
                "author" to author,
                "url" to null as String?
            )
            deliver(payload)
        }
        refreshStatus()
    }

    /// Counts a distinct observed post once; bounds the dedupe set so long
    /// sessions cannot grow memory without limit.
    private fun rememberObserved(hash: Int) {
        if (!observedHashes.add(hash)) return
        observedPosts++
        if (observedHashes.size > MAX_OBSERVED_HASHES) {
            val iterator = observedHashes.iterator()
            repeat(200) { if (iterator.hasNext()) { iterator.next(); iterator.remove() } }
        }
    }

    /// Forwards to Flutter when an engine is listening; otherwise buffers the
    /// post so it is processed the next time the app opens.
    private fun deliver(payload: Map<String, String?>) {
        val target = listener
        if (target != null) {
            try {
                target(payload)
                return
            } catch (_: Exception) {
                // Fall through to buffering.
            }
        }
        synchronized(pendingPayloads) {
            if (pendingPayloads.size < MAX_PENDING_POSTS) pendingPayloads.add(payload)
        }
    }

    private fun collectTexts(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > MAX_DEPTH || out.size >= MAX_NODES) return
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty() && text.length >= MIN_POST_CHARS / 4) {
            out.add(text)
        }
        for (i in 0 until node.childCount) {
            collectTexts(node.getChild(i), out, depth + 1)
        }
    }

    private fun AccessibilityNodeInfo.recycleCompat() {
        // recycle() was removed in API 33; safe no-op on modern runtimes.
        if (android.os.Build.VERSION.SDK_INT < 33) {
            try {
                javaClass.getMethod("recycle").invoke(this)
            } catch (_: Exception) {
            }
        }
    }

    // ---- live status notification ------------------------------------------

    /// Rebuilds the ongoing, low-priority status notification. Shown from
    /// [onServiceConnected] ("capturing is ON") and refreshed on every scan
    /// tick and every Flutter stats push, so pulling down the shade always
    /// shows the current pipeline counts.
    private fun refreshStatus() {
        if (!isEnabled) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_STATUS,
                    "Radar status",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Live status of the background hiring radar"
                    setShowBadge(false)
                })
        }

        val stats = flutterStats
        val matched = stats["matched"] ?: 0
        val skipped = stats["skipped"] ?: 0
        val aiHiring = stats["aiHiring"] ?: 0
        val aiRejected = stats["aiRejected"] ?: 0
        val aiFailed = stats["aiFailed"] ?: 0
        val saved = stats["saved"] ?: 0

        val body = buildString {
            if (observedPosts == 0) {
                append("Capturing is ON. Open LinkedIn and scroll — every post you pass is counted here live.")
            } else {
                append("Posts seen: $observedPosts  ·  passed 1st filter: $gatePassedPosts\n")
                if (filterMode == "prefs") {
                    append("2nd filter (your preferences): matched $matched  ·  skipped $skipped\n")
                } else {
                    append("2nd filter (hiring score): passed $matched  ·  skipped $skipped\n")
                }
                append("AI: confirmed $aiHiring  ·  rejected $aiRejected  ·  failed $aiFailed\n")
                append("Saved to your inbox: $saved")
            }
            if (listener == null) {
                append("\nOpen the FeedRadar app so captured posts can be analyzed.")
            }
        }
        val summary = if (observedPosts == 0) {
            "Capturing is ON"
        } else {
            "Seen $observedPosts · saved $saved"
        }

        val openApp = PendingIntent.getActivity(
            this,
            2002,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_STATUS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("FeedRadar radar is capturing")
            .setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openApp)
            .build()
        manager.notify(STATUS_NOTIFICATION_ID, notification)
    }

    override fun onInterrupt() {
        // Nothing to interrupt: this service performs no actions.
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        isEnabled = false
        instance = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(STATUS_NOTIFICATION_ID)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isEnabled = false
        instance = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(STATUS_NOTIFICATION_ID)
        super.onDestroy()
    }
}

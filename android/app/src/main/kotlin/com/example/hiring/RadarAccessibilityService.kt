package com.example.hiring

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.os.SystemClock

/**
 * Passive feed scanner. Reads visible text nodes in the LinkedIn app while the
 * user scrolls, applies a local keyword gate, and forwards candidate posts to
 * Flutter over the app.hiringradar/share channel. It NEVER clicks, types,
 * focuses, or sends anything: read-only observation.
 */
class RadarAccessibilityService : AccessibilityService() {

    companion object {
        const val LINKEDIN_PACKAGE = "com.linkedin.android"
        const val MIN_POST_CHARS = 60
        const val MAX_POST_CHARS = 4000
        private const val MIN_EVENT_INTERVAL_MS = 1500L
        private const val MAX_NODES = 600
        private const val MAX_DEPTH = 40

        /// Set by MainActivity once the Flutter engine is ready.
        @Volatile
        var onPostCaptured: ((Map<String, String?>) -> Unit)? = null

        @Volatile
        var isEnabled: Boolean = false
    }

    private var lastEmitElapsedMs = 0L
    private val seenHashes = LinkedHashSet<Int>()

    private val keywordGate = listOf(
        "hiring", "join our team", "join the team", "we are hiring", "we're hiring",
        "open role", "open position", "job opening", "looking for a", "looking for an",
        "apply now", "apply here", "send your resume", "dm me", "comment interested",
        "vacancy", "vacancies", "careers", "recruiting", "recruiter", "job alert",
        "immediate joiner", "walk-in", "walk in interview", "freelance opportunity"
    )

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
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val root: AccessibilityNodeInfo = rootInActiveWindow ?: return
        if (root.packageName?.toString() != LINKEDIN_PACKAGE) return

        val now = SystemClock.elapsedRealtime()
        if (now - lastEmitElapsedMs < MIN_EVENT_INTERVAL_MS) return
        lastEmitElapsedMs = now

        val texts = ArrayList<String>()
        collectTexts(root, texts, 0)
        root.recycleCompat()
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
            val lower = text.lowercase()
            if (keywordGate.none { lower.contains(it) }) continue
            val hash = text.hashCode()
            if (!seenHashes.add(hash)) continue
            if (seenHashes.size > 300) {
                val iterator = seenHashes.iterator()
                repeat(100) { if (iterator.hasNext()) { iterator.next(); iterator.remove() } }
            }
            val payload = mapOf(
                "text" to text,
                "author" to author,
                "url" to null as String?
            )
            try {
                onPostCaptured?.invoke(payload)
            } catch (_: Exception) {
                // Never crash the service on Dart-side issues.
            }
        }
    }

    private fun collectTexts(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > MAX_DEPTH || out.size > MAX_NODES) return
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

    override fun onInterrupt() {
        // Nothing to interrupt: this service performs no actions.
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        isEnabled = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isEnabled = false
        super.onDestroy()
    }
}

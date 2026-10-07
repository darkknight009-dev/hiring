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
        const val MAX_POST_CHARS = 8000
        const val MAX_PROFILE_CHARS = 8000
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

        /// Set by MainActivity so every capture-state change — the in-app
        /// control, the notification-shade action, or the system binding or
        /// unbinding this service — reaches Flutter and all screens agree.
        @Volatile
        var stateListener: ((Map<String, Boolean>) -> Unit)? = null
            private set

        /// Persists the pause flag when the service itself is not running, so a
        /// pause set from the app before accessibility was granted still
        /// survives process death.
        @Volatile
        private var appContext: Context? = null

        @Volatile
        var isEnabled: Boolean = false

        /// True when the user asked to stop capturing. The service stays
        /// enabled — pausing never calls [disableSelf], so resuming needs no
        /// new accessibility permission. Survives process death via prefs.
        @Volatile
        var isPaused: Boolean = false
            private set

        /// User's job preferences, pushed from Flutter. When set, the gate
        /// mirrors the Dart-side filter exactly: a post must mention one of
        /// the roles AND (when locations are set) one of the locations.
        /// Generic hiring keywords are only used when no preferences exist.
        @Volatile
        var userRoles: List<String> = emptyList()

        @Volatile
        var userLocations: List<String> = emptyList()

        const val ACTION_PAUSE = "app.hiringradar.action.PAUSE_RADAR"
        const val ACTION_RESUME = "app.hiringradar.action.RESUME_RADAR"
        private const val PREFS_NAME = "radar_state"
        private const val KEY_PAUSED = "paused"

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

        /// Registers the Flutter listener and drains posts buffered while no
        /// engine was listening. Returns the drained posts instead of pushing
        /// them: this runs before the Dart isolate has subscribed to the
        /// stream, so Dart pulls them explicitly once it is ready.
        fun attach(newListener: ((Map<String, String?>) -> Unit)?): List<Map<String, String?>> {
            listener = newListener
            val drained = ArrayList<Map<String, String?>>()
            if (newListener != null) {
                while (true) {
                    val payload = synchronized(pendingPayloads) {
                        pendingPayloads.removeFirstOrNull()
                    } ?: break
                    drained.add(payload)
                }
            }
            instance?.refreshStatus()
            return drained
        }

        /// Registers the callback that mirrors capture state into Flutter. Pass
        /// a null listener from MainActivity.onDestroy to detach.
        fun attachState(
            context: Context,
            newStateListener: ((Map<String, Boolean>) -> Unit)?
        ) {
            appContext = context.applicationContext
            stateListener = newStateListener
        }

        private fun emitState() {
            val payload = mapOf("enabled" to isEnabled, "paused" to isPaused)
            try {
                stateListener?.invoke(payload)
            } catch (_: Throwable) {
                // A dying Flutter engine must never take the radar down with it.
            }
        }

        /// Called from the method channel with the Flutter-side counters
        /// (second filter, AI verdicts, saves) so the status notification
        /// reflects the whole pipeline in realtime.
        fun applyFlutterStats(stats: Map<String, Int>, mode: String) {
            flutterStats = stats
            filterMode = mode
            instance?.refreshStatus()
        }

        /// Stops scanning without giving up accessibility access: the service
        /// stays enabled, so resuming is instant and never sends the user back
        /// to system settings. Used by the in-app control and the notification
        /// action ([ACTION_PAUSE] / [ACTION_RESUME]).
        fun pauseCapture() = setPaused(true)

        fun resumeCapture() = setPaused(false)

        private fun setPaused(paused: Boolean) {
            isPaused = paused
            // Written through the app context when the service is not running,
            // so the choice is not silently lost on the next process start.
            val context = instance ?: appContext
            context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                ?.edit()
                ?.putBoolean(KEY_PAUSED, paused)
                ?.apply()
            instance?.refreshStatus()
            emitState()
        }
    }

    private var lastEmitElapsedMs = 0L
    private val seenHashes = LinkedHashSet<Int>()
    private val observedHashes = LinkedHashSet<Int>()

    /// True while a LinkedIn profile screen is the active window; set from
    /// TYPE_WINDOW_STATE_CHANGED activity class names.
    private var profileWindow = false
    private var lastProfileHash = 0

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
        // A pause set before the process died must not silently turn back into
        // capturing when the service is recreated.
        isPaused = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PAUSED, false)
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
        emitState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> pauseCapture()
            ACTION_RESUME -> resumeCapture()
        }
        // The system binds this service; it must never be restarted on its own.
        return START_NOT_STICKY
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || isPaused) return
        // Tracked before the throttle: a window change is the only signal that
        // the user left (or entered) a profile screen, and dropping it would
        // leave the flag stale for the rest of the session.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val window = event.className?.toString() ?: ""
            profileWindow = window.contains("profile", ignoreCase = true)
        }

        val root: AccessibilityNodeInfo = rootInActiveWindow ?: return
        if (root.packageName?.toString() != LINKEDIN_PACKAGE) return

        val now = SystemClock.elapsedRealtime()
        if (now - lastEmitElapsedMs < MIN_EVENT_INTERVAL_MS) return
        lastEmitElapsedMs = now

        // When the user opens a poster's profile, capture the visible screen
        // (read-only) so Flutter can attach the full profile to the matching
        // saved opportunity. Feed-post scanning is skipped there: a profile
        // page is not a feed card, and its activity list would be captured
        // with the wrong poster.
        if (profileWindow || hasProfileMarker(root)) {
            captureProfileIfNew(root)
            root.recycleCompat()
            refreshStatus()
            return
        }

        // Post-sized own-text nodes anchor a post; each is expanded to its
        // full card so the poster header, body and location lines stay
        // together. A single body node often lacks the role/location keywords
        // the user filters on, which made matching posts get skipped
        // downstream.
        val anchors = ArrayList<AccessibilityNodeInfo>()
        collectAnchors(root, anchors, 0)
        val candidates = anchors
            .sortedByDescending { it.text?.toString()?.trim()?.length ?: 0 }
            .take(4)

        for (node in candidates) {
            val card = cardNodeOf(node)
            val text = cardText(card, StringBuilder(), 0).trim()
            if (text.length !in MIN_POST_CHARS..MAX_POST_CHARS) continue

            // Count distinct posts viewed this session (first filter input).
            rememberObserved(text.hashCode())

            if (!passesGate(text.lowercase())) continue
            val hash = text.hashCode()
            if (!seenHashes.add(hash)) continue
            if (seenHashes.size > 300) {
                val iterator = seenHashes.iterator()
                repeat(100) { if (iterator.hasNext()) { iterator.next(); iterator.remove() } }
            }
            gatePassedPosts++

            // Poster name and headline come from the card's own header lines,
            // so every capture keeps the person who posted along with the
            // full post text.
            val lines = ArrayList<String>()
            collectLines(card, lines, 0)
            var authorIndex = -1
            var author: String? = null
            for (i in lines.indices) {
                val name = personNameOf(lines[i])
                if (name != null) {
                    author = name
                    authorIndex = i
                    break
                }
            }
            val headline = authorHeadline(lines, authorIndex)
            val payload = mapOf(
                "kind" to "post",
                "text" to text,
                "author" to author,
                "headline" to headline,
                "url" to null as String?
            )
            deliver(payload)
        }
        root.recycleCompat()
        refreshStatus()
    }

    /// Captures the visible profile screen once per distinct content while
    /// the user views it. Flutter matches it to an opportunity by poster
    /// name; a wrong guess here is harmless because the match happens there.
    private fun captureProfileIfNew(root: AccessibilityNodeInfo) {
        val lines = ArrayList<String>()
        collectLines(root, lines, 0)
        val text = lines.joinToString("\n")
        if (text.length < 120) return // still loading, or not a real profile
        val capped =
            if (text.length > MAX_PROFILE_CHARS) text.substring(0, MAX_PROFILE_CHARS) else text
        val hash = capped.hashCode()
        if (hash == lastProfileHash) return
        lastProfileHash = hash
        deliver(mapOf("kind" to "profile", "text" to capped, "url" to null as String?))
    }

    /// Lines LinkedIn only renders on a profile screen. A second signal for
    /// builds where the window class name does not contain "profile".
    private val profileMarkers = setOf(
        "contact info", "show all activity", "all activity", "open to"
    )

    private fun hasProfileMarker(root: AccessibilityNodeInfo): Boolean {
        var budget = MAX_NODES
        fun walk(node: AccessibilityNodeInfo?, depth: Int): Boolean {
            if (node == null || depth > MAX_DEPTH || budget-- <= 0) return false
            val line = node.text?.toString()?.trim()?.lowercase()
            if (line != null && line in profileMarkers) return true
            for (i in 0 until node.childCount) {
                if (walk(node.getChild(i), depth + 1)) return true
            }
            return false
        }
        return walk(root, 0)
    }

    /// First-filter gate. With preferences set it mirrors the Dart-side
    /// `matchesJobPreferences` exactly (roles AND locations, each an OR-list),
    /// so "passed 1st filter" in the shade is no longer inflated by generic
    /// hiring posts the second filter would reject anyway. Without
    /// preferences the generic hiring keyword gate applies.
    private fun passesGate(lower: String): Boolean {
        val roles = userRoles
        val locations = userLocations
        if (roles.isNotEmpty() || locations.isNotEmpty()) {
            fun anyMentioned(list: List<String>): Boolean {
                val keywords = list.filter { it.isNotBlank() }
                return keywords.isEmpty() ||
                    keywords.any { lower.contains(it.lowercase()) }
            }
            return anyMentioned(roles) && anyMentioned(locations)
        }
        return keywordGate.any { lower.contains(it) }
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

    /// Every non-empty own-text line in document order, including the short
    /// header lines (poster name, headline) that [cardText] skips.
    private fun collectLines(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > MAX_DEPTH || out.size >= MAX_NODES) return
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty()) out.add(text)
        for (i in 0 until node.childCount) {
            collectLines(node.getChild(i), out, depth + 1)
        }
    }

    /// LinkedIn's own chrome labels, which can look person-shaped to a
    /// two-word heuristic ("Easy Apply", "View profile", …).
    private val uiLabels = setOf(
        "like", "comment", "repost", "send", "share", "follow", "following",
        "connect", "subscribe", "see more", "…more", "...more", "show more",
        "view translation", "open to", "promoted", "ad", "learn more",
        "apply", "easy apply", "interested", "celebrate", "insightful",
        "support", "curious", "more", "message", "home", "network", "jobs",
        "messaging", "notifications", "search", "see all", "view all",
        "mutual connections", "contact info", "show all activity"
    )

    private val timestampLine = Regex(
        "^(just now|\\d+\\s*(s|min|mins|minute|minutes|h|hr|hrs|hour|hours|" +
            "d|day|days|w|wk|week|weeks|m|mo|month|months|y|yr|year|years)s?\\b).*",
        RegexOption.IGNORE_CASE
    )

    /// Extracts a person (or company page) name from a card header line:
    /// short, word-like, no digits or URLs, not one of LinkedIn's labels.
    /// Returns the name without a trailing "· 2nd" degree suffix, or null.
    private fun personNameOf(line: String): String? {
        val candidate = line.substringBefore('·').trim()
        if (candidate.length !in 2..40) return null
        if (candidate.contains("http")) return null
        if (candidate.any { it.isDigit() }) return null
        if (!candidate.any { it.isLetter() }) return null
        val lower = candidate.lowercase()
        if (lower in uiLabels || lower.startsWith("view ")) return null
        val words = candidate.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size < 2) return null
        return candidate
    }

    /// The headline LinkedIn renders under the poster name and before the
    /// post body. Timestamp and chrome lines are skipped; the scan stops at
    /// the first body-sized line.
    private fun authorHeadline(lines: List<String>, authorIndex: Int): String? {
        if (authorIndex < 0) return null
        for (i in authorIndex + 1 until lines.size) {
            val line = lines[i]
            if (line.length >= MIN_POST_CHARS) return null // reached the body
            if (line.length !in 4..120) continue
            val lower = line.lowercase()
            if (lower in uiLabels || lower.startsWith("view ")) continue
            if (timestampLine.matches(line)) continue
            if (!line.any { it.isLetter() }) continue
            return line
        }
        return null
    }

    /// Nodes whose own text is post-sized; each one anchors a post card.
    private fun collectAnchors(
        node: AccessibilityNodeInfo?,
        out: MutableList<AccessibilityNodeInfo>,
        depth: Int
    ) {
        if (node == null || depth > MAX_DEPTH || out.size >= MAX_NODES) return
        val length = node.text?.toString()?.trim()?.length ?: 0
        if (length in MIN_POST_CHARS..MAX_POST_CHARS) out.add(node)
        for (i in 0 until node.childCount) {
            collectAnchors(node.getChild(i), out, depth + 1)
        }
    }

    /// Walks up from an anchor while the ancestor still looks like a single
    /// post card: exactly one post-sized text block in its subtree and a
    /// bounded total length. Returns the card node so the poster header lines
    /// can be read from the same card as the body.
    private fun cardNodeOf(anchor: AccessibilityNodeInfo): AccessibilityNodeInfo {
        var current = anchor
        var guard = 0
        while (guard++ < MAX_DEPTH) {
            val parent = current.parent ?: break
            if (countLongTexts(parent, 0) > 1) break
            if (cardText(parent, StringBuilder(), 0).length > MAX_POST_CHARS) break
            current = parent
        }
        return current
    }

    /// Counts post-sized own-text nodes in a subtree; exits early at two.
    private fun countLongTexts(node: AccessibilityNodeInfo?, depth: Int): Int {
        if (node == null || depth > MAX_DEPTH) return 0
        var count = 0
        val length = node.text?.toString()?.trim()?.length ?: 0
        if (length >= MIN_POST_CHARS) count++
        for (i in 0 until node.childCount) {
            count += countLongTexts(node.getChild(i), depth + 1)
            if (count > 1) return count
        }
        return count
    }

    private fun cardText(node: AccessibilityNodeInfo?, out: StringBuilder, depth: Int): String {
        if (node == null || depth > MAX_DEPTH || out.length > MAX_POST_CHARS) {
            return out.toString()
        }
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty() && text.length >= MIN_POST_CHARS / 4) {
            if (out.isNotEmpty()) out.append('\n')
            out.append(text)
        }
        for (i in 0 until node.childCount) {
            cardText(node.getChild(i), out, depth + 1)
        }
        return out.toString()
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

        val paused = isPaused
        val body = buildString {
            if (paused) {
                append("Capture is paused — nothing is being read. Tap Resume to start again; your accessibility access is still granted.")
            } else if (observedPosts == 0) {
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
            if (!paused && listener == null) {
                append("\nOpen the FeedRadar app so captured posts can be analyzed.")
            }
        }
        val summary = when {
            paused -> "Paused"
            observedPosts == 0 -> "Capturing is ON"
            else -> "Seen $observedPosts · saved $saved"
        }

        val openApp = PendingIntent.getActivity(
            this,
            2002,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // One action that flips between pausing and resuming. Pausing never
        // disables the service, so resuming needs no new permission.
        val toggleCapture = PendingIntent.getService(
            this,
            2003,
            Intent(this, RadarAccessibilityService::class.java)
                .setAction(if (paused) ACTION_RESUME else ACTION_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_STATUS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(
                if (paused) "FeedRadar capture is paused"
                else "FeedRadar radar is capturing"
            )
            .setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openApp)
            .addAction(
                if (paused) android.R.drawable.ic_media_play
                else android.R.drawable.ic_menu_close_clear_cancel,
                if (paused) "Resume capture" else "Stop capture",
                toggleCapture
            )
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
        emitState()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isEnabled = false
        instance = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(STATUS_NOTIFICATION_ID)
        emitState()
        super.onDestroy()
    }
}

import '../../app_dependencies.dart';
import '../../models/opportunity.dart';
import '../../models/opportunity_entity.dart';
import '../analysis/ai_provider.dart';
import '../analysis/hiring_filter.dart';
import '../platform/android_bridge.dart';

/// Consumes posts the Android radar observed, applies the offline filter and
/// the user's job preferences, analyzes with AI when a key is configured,
/// saves the opportunity locally, and notifies. Runs only while the app
/// process is alive; nothing is sent anywhere on the user's behalf.
///
/// Posts are processed FIFO from a queue — never dropped while a previous
/// analysis is in flight. After every pipeline step the counters are pushed
/// to the native status notification so the shade reflects reality in
/// realtime.
class RadarCapture {
  RadarCapture(this._deps);

  final AppDependencies _deps;
  final _recentHashes = <int>[];
  final _queue = <RadarPost>[];
  bool _draining = false;

  static const _maxRemembered = 60;

  // ---- pipeline counters, pushed to the native status notification --------

  /// Passed the first (native keyword) filter and reached this pipeline.
  int _matched = 0;

  /// Dropped by the second filter (preferences or hiring score).
  int _skipped = 0;

  /// AI verdicts.
  int _aiHiring = 0;
  int _aiRejected = 0;
  int _aiFailed = 0;

  /// Opportunities written to the local inbox.
  int _saved = 0;

  void start() {
    syncPreferences();
    AndroidBridge.radarPosts.listen((post) {
      // Enqueue and drain one at a time: slow AI calls delay later posts but
      // never discard them.
      _queue.add(post);
      _drain();
    });
    // Subscribe first, then pull: posts captured while no engine was
    // listening are flushed into the stream by this call.
    AndroidBridge.startRadarListener();
  }

  /// Pushes the user's job preferences into the native radar pre-filter so
  /// its keyword gate mirrors the Dart-side filter. Called at startup and
  /// whenever preferences change in the UI.
  void syncPreferences() {
    final settings = _deps.settings;
    AndroidBridge.updateRadarKeywords(
      roles: settings.preferredRoles,
      locations: settings.preferredLocations,
    );
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final post = _queue.removeAt(0);
        await _handle(post);
      }
    } finally {
      _draining = false;
    }
  }

  /// Reports the counters to the native status notification. Failures are
  /// ignored: stats are best-effort and must never break capture.
  void _publishStats() {
    final settings = _deps.settings;
    AndroidBridge.updateRadarStats({
      'matched': _matched,
      'skipped': _skipped,
      'aiHiring': _aiHiring,
      'aiRejected': _aiRejected,
      'aiFailed': _aiFailed,
      'saved': _saved,
    }, mode: settings.hasJobPreferences ? 'prefs' : 'score');
  }

  Future<void> _handle(RadarPost post) async {
    if (post.kind == 'profile') {
      await _attachProfile(post);
      return;
    }
    final hash = post.text.hashCode;
    if (_recentHashes.contains(hash)) return;
    _recentHashes.add(hash);
    if (_recentHashes.length > _maxRemembered) {
      _recentHashes.removeAt(0);
    }

    // Already in the inbox from an earlier session (e.g. re-scrolled after a
    // reinstall, where in-memory dedupe no longer applies)? Never duplicate.
    final existing = await _deps.repository.loadAll();
    if (existing.any((o) => o.text != null && o.text == post.text)) return;

    final settings = _deps.settings;
    final prefsMatch = settings.matchesJobPreferences(post.text);
    final scoreMatch = looksLikeHiringPost(
      post.text,
      threshold: settings.filterThreshold,
    );
    // The user's own preferences are the filter when set: only posts matching
    // their roles (and locations, if set) are captured. Otherwise the offline
    // hiring score decides.
    final passes = settings.hasJobPreferences ? prefsMatch : scoreMatch;
    if (!passes) {
      _skipped++;
      _publishStats();
      return;
    }
    _matched++;
    _publishStats();

    PostAnalysis analysis;
    try {
      final result = await _deps.ai.analyzePost(text: post.text);
      analysis = result.analysis;
      if (!analysis.isHiring) {
        // AI confirmed it is not a hiring post.
        _aiRejected++;
        _publishStats();
        return;
      }
      _aiHiring++;
    } on AiAnalysisException {
      _aiFailed++;
      analysis = const PostAnalysis(
        isHiring: true,
        confidence: null,
        summary: 'Captured by radar; AI analysis failed. Analyze again from the inbox.',
      );
    }

    final opportunity = Opportunity(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      status: 'new',
      analysis: analysis,
      text: post.text,
      capturedVia: 'radar',
      posterName: post.author ?? analysis.posterName,
      posterHeadline: post.headline,
    );
    await _deps.repository.save(opportunity);
    await _deps.setPendingCapture(null);
    _saved++;
    _publishStats();

    await AndroidBridge.showNotification(
      title: 'New hiring post captured',
      body: opportunity.displayTitle,
      id: opportunity.id.hashCode,
    );
    _deps.dataChanged();
  }

  /// Attaches a captured poster-profile screen to the saved opportunity whose
  /// poster name appears near the top of the profile text. Profiles that
  /// match nothing are silently dropped; they were for someone else's page.
  Future<void> _attachProfile(RadarPost profile) async {
    final text = profile.text;
    final head = (text.length > 600 ? text.substring(0, 600) : text)
        .toLowerCase();
    final all = await _deps.repository.loadAll();
    for (final opportunity in all) {
      final name = opportunity.posterName;
      if (name == null || name.isEmpty) continue;
      if (!head.contains(name.toLowerCase())) continue;
      if (opportunity.posterProfile == text) return;
      await _deps.repository.save(opportunity.copyWith(posterProfile: text));
      _deps.dataChanged();
      return;
    }
  }
}

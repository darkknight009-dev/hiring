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
class RadarCapture {
  RadarCapture(this._deps);

  final AppDependencies _deps;
  final _recentHashes = <int>[];
  bool _busy = false;

  static const _maxRemembered = 60;

  void start() {
    syncPreferences();
    AndroidBridge.radarPosts.listen((post) {
      // Serialize processing: one AI call at a time, drop overlaps.
      if (_busy) return;
      _busy = true;
      _handle(post).whenComplete(() => _busy = false);
    });
  }

  /// Pushes the user's job preferences into the native radar pre-filter so
  /// its keyword gate admits posts the user actually cares about. Called at
  /// startup and whenever preferences change in the UI.
  void syncPreferences() {
    final settings = _deps.settings;
    AndroidBridge.updateRadarKeywords([
      ...settings.preferredRoles,
      ...settings.preferredLocations,
    ]);
  }

  Future<void> _handle(RadarPost post) async {
    final hash = post.text.hashCode;
    if (_recentHashes.contains(hash)) return;
    _recentHashes.add(hash);
    if (_recentHashes.length > _maxRemembered) {
      _recentHashes.removeAt(0);
    }

    final settings = _deps.settings;
    if (settings.hasJobPreferences) {
      // The user's own preferences are the filter: only posts matching their
      // roles (and locations, if set) are captured.
      if (!settings.matchesJobPreferences(post.text)) return;
    } else if (!looksLikeHiringPost(
      post.text,
      threshold: settings.filterThreshold,
    )) {
      return;
    }

    PostAnalysis analysis;
    final ai = _deps.ai;
    if (ai != null) {
      try {
        final result = await ai.analyzePost(text: post.text);
        analysis = result.analysis;
        if (!analysis.isHiring) return; // AI confirmed it is not a hiring post.
      } on AiAnalysisException {
        analysis = const PostAnalysis(
          isHiring: true,
          confidence: null,
          summary: 'Captured by radar; AI analysis failed. Analyze again from the inbox.',
        );
      }
    } else {
      analysis = const PostAnalysis(
        isHiring: true,
        confidence: null,
        summary: 'Captured by radar; no AI key configured yet.',
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
    );
    await _deps.repository.save(opportunity);
    await _deps.setPendingCapture(null);

    await AndroidBridge.showNotification(
      title: 'New hiring post captured',
      body: opportunity.displayTitle,
      id: opportunity.id.hashCode,
    );
    _deps.dataChanged();
  }
}

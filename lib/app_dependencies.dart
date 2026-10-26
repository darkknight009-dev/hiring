import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/captured_post.dart';
import 'services/analysis/ai_provider.dart';
import 'services/analysis/nvidia_ai_provider.dart';
import 'services/opportunities/opportunity_repository.dart';
import 'services/settings/settings_store.dart';

/// Widget-scoped dependency container. Created once in main() and passed to
/// the app; features reach it through `context.dep`.
class AppDependencies extends ChangeNotifier {
  AppDependencies({required this.prefs, this.aiOverride})
    : settings = SettingsStore(prefs: prefs),
      repository = OpportunityRepository(prefs: prefs);

  final SharedPreferences prefs;
  final SettingsStore settings;
  final OpportunityRepository repository;

  final _pendingCaptures = <CapturedPost>[];
  final AiProvider? aiOverride;
  AiProvider? _ai;

  /// A shared-in post waiting to be analyzed. The shell navigates to the
  /// capture screen when this is set.
  bool get hasPendingCapture => _pendingCaptures.isNotEmpty;

  CapturedPost? get pendingCapture =>
      _pendingCaptures.isEmpty ? null : _pendingCaptures.first;

  /// NVIDIA NIM is configured with the user's local-only key. Tests inject
  /// [aiOverride] to stay off the network.
  AiProvider get ai => _ai ??= aiOverride ?? NvidiaAiProvider(
    apiKey: settings.apiKey ?? '',
    model: settings.model.isEmpty
        ? NvidiaAiProvider.defaultModel
        : settings.model,
  );

  /// Rebuilds the provider after runtime AI settings change.
  void resetAiProvider() {
    if (aiOverride != null) return;
    _ai = null;
    notifyListeners();
  }

  /// Public signal for services (radar, outreach) that mutate data outside
  /// the widget tree and need the UI to refresh.
  void dataChanged() => notifyListeners();

  Future<void> setPendingCapture(CapturedPost? post) async {
    if (post == null) {
      _pendingCaptures.clear();
    } else {
      _pendingCaptures.add(post);
    }
    notifyListeners();
  }

  /// Consumes the pending share so it is analyzed exactly once.
  CapturedPost? takePendingCapture() {
    if (_pendingCaptures.isEmpty) return null;
    final value = _pendingCaptures.removeAt(0);
    return value;
  }
}

extension DepsContext on BuildContext {
  /// Dependency accessor. The scope is set once at startup and never changes,
  /// so this reads without registering dependencies.
  AppDependencies get dep {
    final widget = getInheritedWidgetOfExactType<_DepsInherited>();
    if (widget == null) {
      throw StateError('AppDependenciesScope is missing above this context.');
    }
    return widget.deps;
  }
}

class _DepsInherited extends InheritedWidget {
  const _DepsInherited({required this.deps, required super.child});
  final AppDependencies deps;

  @override
  bool updateShouldNotify(_DepsInherited oldWidget) => false;
}

class AppDependenciesScope extends StatelessWidget {
  const AppDependenciesScope({
    super.key,
    required this.deps,
    required this.child,
  });

  final AppDependencies deps;
  final Widget child;

  static AppDependencies of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<_DepsInherited>();
    if (widget == null) {
      throw StateError('AppDependenciesScope is missing above this context.');
    }
    return widget.deps;
  }

  @override
  Widget build(BuildContext context) =>
      _DepsInherited(deps: deps, child: child);
}

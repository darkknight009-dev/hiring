import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/captured_post.dart';
import 'services/analysis/ai_provider.dart';
import 'services/analysis/gemini_ai_provider.dart';
import 'services/opportunities/opportunity_repository.dart';
import 'services/settings/settings_store.dart';

/// Widget-scoped dependency container. Created once in main() and passed to
/// the app; features reach it through `context.dep`.
class AppDependencies extends ChangeNotifier {
  AppDependencies({required this.prefs})
    : settings = SettingsStore(prefs: prefs),
      repository = OpportunityRepository(prefs: prefs);

  final SharedPreferences prefs;
  final SettingsStore settings;
  final OpportunityRepository repository;

  CapturedPost? _pendingCapture;
  AiProvider? _ai;
  AiProviderKind? _builtFor;
  String? _builtForModel;

  /// A shared-in post waiting to be analyzed. The shell navigates to the
  /// capture screen when this is set.
  bool get hasPendingCapture => _pendingCapture != null;

  /// Builds the AI provider from stored settings, or null without a key.
  AiProvider? get ai {
    final apiKey = settings.apiKey;
    if (apiKey == null || apiKey.isEmpty) return null;
    final model = settings.model.isEmpty
        ? GeminiAiProvider.defaultModel
        : settings.model;
    if (_builtFor != settings.provider ||
        _builtForModel != model ||
        _ai == null) {
      switch (settings.provider) {
        case AiProviderKind.gemini:
          _ai = GeminiAiProvider(apiKey: apiKey, model: model);
        case AiProviderKind.openRouter:
          _ai = null; // Not yet connected; the UI communicates this honestly.
      }
      _builtFor = settings.provider;
      _builtForModel = model;
    }
    return _ai;
  }

  bool get hasAiKey => (settings.apiKey ?? '').isNotEmpty;

  /// Public signal for services (radar, outreach) that mutate data outside
  /// the widget tree and need the UI to refresh.
  void dataChanged() => notifyListeners();

  Future<void> setPendingCapture(CapturedPost? post) async {
    _pendingCapture = post;
    notifyListeners();
  }

  /// Consumes the pending share so it is analyzed exactly once.
  CapturedPost? takePendingCapture() {
    final value = _pendingCapture;
    _pendingCapture = null;
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

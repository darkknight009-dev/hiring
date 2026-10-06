import 'package:shared_preferences/shared_preferences.dart';

import '../../models/opportunity_entity.dart';

/// Where AI analysis runs and which key it uses. Keys stay on the device.
enum AiProviderKind { gemini, openRouter, nvidia }

class SettingsStore {
  SettingsStore({required this.prefs});

  final SharedPreferences prefs;

  static const _keyProvider = 'ai.provider';
  static const _keyKey = 'ai.apiKey';
  static const _keyModel = 'ai.model';
  static const _keyThreshold = 'filter.threshold';
  static const _keyStatuses = 'opportunity.statuses';
  static const _keyProfileName = 'profile.name';
  static const _keyProfileHeadline = 'profile.headline';
  static const _keyProfileSkills = 'profile.skills';
  static const _keyProfileTone = 'profile.tone';
  static const _keyResumePath = 'resume.path';
  static const _keyReminderHours = 'radar.reminderHours';
  static const _keyOnboarded = 'onboarding.done';
  static const _keyPrefRoles = 'prefs.roles';
  static const _keyPrefLocations = 'prefs.locations';

  AiProviderKind get provider => switch (prefs.getString(_keyProvider)) {
    'openRouter' => AiProviderKind.openRouter,
    'nvidia' => AiProviderKind.nvidia,
    _ => AiProviderKind.gemini,
  };

  Future<void> setProvider(AiProviderKind value) =>
      prefs.setString(_keyProvider, value.name);

  String? get apiKey => prefs.getString(_keyKey);

  Future<void> setApiKey(String? value) => value == null || value.isEmpty
      ? prefs.remove(_keyKey)
      : prefs.setString(_keyKey, value);

  String get model => prefs.getString(_keyModel) ?? '';

  Future<void> setModel(String? value) => value == null || value.trim().isEmpty
      ? prefs.remove(_keyModel)
      : prefs.setString(_keyModel, value.trim());

  int get filterThreshold {
    final value = prefs.getInt(_keyThreshold);
    return value == null || value < 1 || value > 10 ? 4 : value;
  }

  Future<void> setFilterThreshold(int value) =>
      prefs.setInt(_keyThreshold, value.clamp(1, 10));
  List<String> get statuses {
    final stored = prefs.getStringList(_keyStatuses);
    final valid =
        stored?.where(Opportunity.statuses.contains).toList() ?? const [];
    return valid.isEmpty
        ? List.unmodifiable(Opportunity.statuses)
        : List.unmodifiable(valid);
  }

  Future<void> setStatuses(List<String> value) =>
      prefs.setStringList(_keyStatuses, value);

  String get profileName => prefs.getString(_keyProfileName) ?? '';
  Future<void> setProfileName(String value) =>
      prefs.setString(_keyProfileName, value.trim());

  String get profileHeadline => prefs.getString(_keyProfileHeadline) ?? '';
  Future<void> setProfileHeadline(String value) =>
      prefs.setString(_keyProfileHeadline, value.trim());

  String get profileSkills => prefs.getString(_keyProfileSkills) ?? '';
  Future<void> setProfileSkills(String value) =>
      prefs.setString(_keyProfileSkills, value.trim());

  String get profileTone {
    final value = prefs.getString(_keyProfileTone);
    return const {'professional', 'warm', 'direct'}.contains(value)
        ? value!
        : 'professional';
  }

  Future<void> setProfileTone(String value) =>
      prefs.setString(_keyProfileTone, value);

  /// On-device path of the stored resume PDF (Android only today).
  String? get resumePath => prefs.getString(_keyResumePath);
  Future<void> setResumePath(String? value) => value == null || value.isEmpty
      ? prefs.remove(_keyResumePath)
      : prefs.setString(_keyResumePath, value);

  /// How often reminder notifications repeat while a connection request is
  /// awaiting acceptance.
  int get reminderHours {
    final value = prefs.getInt(_keyReminderHours);
    return const [4, 12, 24, 48].contains(value) ? value! : 12;
  }

  Future<void> setReminderHours(int value) =>
      prefs.setInt(_keyReminderHours, value);

  /// Whether the first-launch onboarding has been completed.
  bool get onboarded => prefs.getBool(_keyOnboarded) ?? false;

  Future<void> setOnboarded(bool value) => prefs.setBool(_keyOnboarded, value);

  /// Job roles or keywords the radar should watch for, e.g. `Flutter developer`.
  List<String> get preferredRoles => _keywordList(_keyPrefRoles);

  Future<void> setPreferredRoles(List<String> value) =>
      prefs.setStringList(_keyPrefRoles, _cleanKeywords(value));

  /// Locations the radar should watch for, e.g. `Bengaluru` or `Remote`.
  List<String> get preferredLocations => _keywordList(_keyPrefLocations);

  Future<void> setPreferredLocations(List<String> value) =>
      prefs.setStringList(_keyPrefLocations, _cleanKeywords(value));

  bool get hasJobPreferences =>
      preferredRoles.isNotEmpty || preferredLocations.isNotEmpty;

  /// The radar-side filter: a post is captured only when it matches the user's
  /// job preferences. Roles and locations each act as OR-lists; when both are
  /// set a post must mention at least one of each. No preferences means every
  /// hiring post passes.
  bool matchesJobPreferences(String text) {
    final roles = preferredRoles;
    final locations = preferredLocations;
    if (roles.isEmpty && locations.isEmpty) return true;
    final normalized = text.toLowerCase();
    bool anyMentioned(List<String> needles) =>
        needles.any((needle) => normalized.contains(needle.toLowerCase()));
    if (roles.isNotEmpty && !anyMentioned(roles)) return false;
    if (locations.isNotEmpty && !anyMentioned(locations)) return false;
    return true;
  }

  List<String> _keywordList(String key) => List.unmodifiable(
    (prefs.getStringList(key) ?? const <String>[])
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty),
  );

  static List<String> _cleanKeywords(List<String> value) => value
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

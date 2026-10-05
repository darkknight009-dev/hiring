import 'package:shared_preferences/shared_preferences.dart';

import '../../models/opportunity_entity.dart';

/// Where AI analysis runs and which key it uses. Keys stay on the device.
enum AiProviderKind { gemini, openRouter }

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

  AiProviderKind get provider {
    final value = prefs.getString(_keyProvider);
    return value == 'openRouter'
        ? AiProviderKind.openRouter
        : AiProviderKind.gemini;
  }

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
}

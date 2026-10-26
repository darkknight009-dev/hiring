import '../settings/settings_store.dart';

const supportsPersistentStorage = false;

Future<String?> pickAndStore(SettingsStore settings) async => null;

Future<void> clear(SettingsStore settings) async {
  await settings.setResumePath(null);
}

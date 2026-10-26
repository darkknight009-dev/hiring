import '../settings/settings_store.dart';
import 'resume_store_io.dart'
    if (dart.library.js_interop) 'resume_store_web.dart' as impl;

/// Stores the user's resume PDF in app-private storage and remembers the path.
/// The file never leaves the device except as an attachment the user chooses
/// to send from their own email app.
class ResumeStore {
  ResumeStore(this._settings);

  final SettingsStore _settings;

  String? get storedPath => _settings.resumePath;

  bool get supportsPersistentStorage => impl.supportsPersistentStorage;

  Future<String?> pickAndStore() => impl.pickAndStore(_settings);

  Future<void> clear() => impl.clear(_settings);
}

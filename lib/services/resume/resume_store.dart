import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../settings/settings_store.dart';

/// Stores the user's resume PDF in app-private storage and remembers the path.
/// The file never leaves the device except as an attachment the user chooses
/// to send from their own email app.
class ResumeStore {
  ResumeStore(this._settings);

  final SettingsStore _settings;

  String? get storedPath => _settings.resumePath;

  Future<String?> pickAndStore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return null; // User cancelled.

    if (kIsWeb || file.path == null) {
      // Web keeps the picked file for this session only (drafts still
      // reference it); persistent resume storage is an Android feature.
      return kIsWeb ? null : null;
    }

    final docs = await getApplicationDocumentsDirectory();
    final resumeDir = Directory('${docs.path}/resume');
    await resumeDir.create(recursive: true);
    final destination = File('${resumeDir.path}/resume.pdf');
    await File(file.path!).copy(destination.path);
    await _settings.setResumePath(destination.path);
    return destination.path;
  }

  Future<void> clear() async {
    final path = _settings.resumePath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // Already gone; clearing the setting is what matters.
      }
    }
    await _settings.setResumePath(null);
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../settings/settings_store.dart';

const supportsPersistentStorage = true;

Future<String?> pickAndStore(SettingsStore settings) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  final file = result?.files.single;
  if (file == null) return null;
  final sourcePath = file.path;
  if (sourcePath == null) {
    throw const FileSystemException('The selected resume has no local path.');
  }

  final docs = await getApplicationDocumentsDirectory();
  final resumeDir = Directory('${docs.path}/resume');
  await resumeDir.create(recursive: true);
  final destination = File('${resumeDir.path}/resume.pdf');
  await File(sourcePath).copy(destination.path);
  await settings.setResumePath(destination.path);
  return destination.path;
}

Future<void> clear(SettingsStore settings) async {
  final path = settings.resumePath;
  if (path != null) {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone; clearing the setting is what matters.
    }
  }
  await settings.setResumePath(null);
}

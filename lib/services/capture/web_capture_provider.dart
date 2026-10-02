import '../../models/captured_post.dart';
import 'capture_provider.dart';

/// Reads explicit user input only. Does not fetch URLs or inspect browser tabs.
/// No dart:html dependency: the same manual flow can be used on Android.
class WebCaptureProvider implements CaptureProvider {
  const WebCaptureProvider({required this.readDraft});

  final CapturedPost? Function() readDraft;

  @override
  Future<CapturedPost?> capturePost() async => readDraft();
}

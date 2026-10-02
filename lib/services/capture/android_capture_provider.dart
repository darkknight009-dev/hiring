import '../../models/captured_post.dart';
import 'capture_provider.dart';

/// Future platform adapter, intentionally not connected to the application.
/// No accessibility service, background observation, or permissions yet.
class AndroidCaptureProvider implements CaptureProvider {
  @override
  Future<CapturedPost?> capturePost() {
    throw UnsupportedError(
      'Android capture is not implemented. Use manual paste capture instead.',
    );
  }
}

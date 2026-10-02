import '../../models/captured_post.dart';

/// The future analysis pipeline consumes this contract, not browser APIs.
abstract class CaptureProvider {
  /// Returns null when a platform capture is cancelled.
  Future<CapturedPost?> capturePost();
}

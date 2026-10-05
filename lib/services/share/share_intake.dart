import 'dart:async';

import '../../models/captured_post.dart';
import 'share_io.dart' if (dart.library.js_interop) 'share_web.dart' as impl;

/// Receives posts shared into the app from the platform share target.
///
/// - Web (PWA): the manifest `share_target` action lands on the start URL with
///   `title`, `text`, and `url` query params; consumed and cleared on load.
/// - Android: ACTION_SEND / ACTION_PROCESS_TEXT intents are forwarded by
///   MainActivity over the `app.hiringradar/share` MethodChannel.
///
/// The conditional import keeps `package:web` out of native builds so the
/// same codebase compiles for both platforms.
class ShareIntake {
  ShareIntake._();

  static final _controller = StreamController<CapturedPost>.broadcast();

  /// Shared posts arriving after startup (Android only today).
  static Stream<CapturedPost> get stream => _controller.stream;

  /// Reads the share that launched the app, if any, and starts listening.
  /// Safe to call once from main().
  static Future<CapturedPost?> init() {
    return impl.init(onShared: (post) => _controller.add(post));
  }
}

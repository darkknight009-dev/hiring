import '../../models/captured_post.dart';
import '../platform/android_bridge.dart';

/// IO platforms (Android today). Shares arrive over the native bridge from the
/// activity, both at launch and while the app is running.
Future<CapturedPost?> init({
  required void Function(CapturedPost) onShared,
}) async {
  final launch = await AndroidBridge.listen();
  AndroidBridge.sharedPosts.listen(onShared);
  return launch;
}

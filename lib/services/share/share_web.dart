import 'dart:async';

import 'package:web/web.dart' as web;

import '../../models/captured_post.dart';
import 'share_parser.dart';

/// Web implementation. The browser share target lands on `/?title=…&text=…&url=…`;
/// params are read from [Uri.base] and then cleared from the address bar so a
/// reload does not re-capture.
Future<CapturedPost?> init({
  required void Function(CapturedPost) onShared,
}) async {
  final post = parseSharedExtras(Uri.base.queryParameters);
  _clearWebQuery();
  return post;
}

void _clearWebQuery() {
  if (Uri.base.queryParameters.isEmpty) return;
  try {
    final clean = Uri(
      scheme: Uri.base.scheme,
      host: Uri.base.host,
      port: Uri.base.hasPort ? Uri.base.port : null,
      path: Uri.base.path,
      fragment: Uri.base.fragment.isEmpty ? null : Uri.base.fragment,
    );
    web.window.history.replaceState(null, '', clean.toString());
  } catch (_) {
    // History API unavailable (e.g. file:// preview); harmless to skip.
  }
}

/// Kept for API parity with the IO implementation.
Stream<CapturedPost> get runtimeShares => const Stream<CapturedPost>.empty();

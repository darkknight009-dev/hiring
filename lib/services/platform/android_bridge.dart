import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../../models/captured_post.dart';
import '../share/share_parser.dart';

/// The one coordinator for the native `app.hiringradar/share` channel.
/// Web builds never register native handlers; every call degrades safely.
class AndroidBridge {
  AndroidBridge._();

  static const _channel = MethodChannel('app.hiringradar/share');
  static bool _listening = false;

  static final _sharedPosts = StreamController<CapturedPost>.broadcast();
  static final _radarPosts = StreamController<RadarPost>.broadcast();

  static Stream<CapturedPost> get sharedPosts => _sharedPosts.stream;
  static Stream<RadarPost> get radarPosts => _radarPosts.stream;

  /// Registers the inbound handler once and returns the launch share, if any.
  static Future<CapturedPost?> listen() async {
    if (kIsWeb) return null;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        switch (call.method) {
          case 'onSharedPost':
            final post = parseSharedExtras(args);
            if (post != null) _sharedPosts.add(post);
          case 'onRadarPost':
            final post = RadarPost.fromExtras(args);
            if (post != null) _radarPosts.add(post);
        }
      });
    }
    try {
      final extras = await _channel.invokeMapMethod<String, Object?>(
        'getLaunchSharing',
      );
      return parseSharedExtras(extras);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<T?> _call<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> isRadarEnabled() async =>
      await _call<bool>('isRadarEnabled') ?? false;

  static Future<void> openAccessibilitySettings() =>
      _call<void>('openAccessibilitySettings');

  static Future<void> requestNotificationPermission() =>
      _call<void>('requestNotificationPermission');

  static Future<void> showNotification({
    required String title,
    required String body,
    int id = 1001,
  }) =>
      _call<void>('showNotification', {'title': title, 'body': body, 'id': id});

  static Future<void> scheduleReminder({
    required String key,
    required String title,
    required String body,
    required Duration interval,
  }) => _call<void>('scheduleReminder', {
    'key': key,
    'title': title,
    'body': body,
    'intervalMillis': interval.inMilliseconds,
  });

  static Future<void> cancelReminder(String key) =>
      _call<void>('cancelReminder', {'key': key});

  /// Pushes the user's job-preference keywords into the native radar so its
  /// pre-filter admits posts the user actually cares about.
  static Future<void> updateRadarKeywords(List<String> keywords) =>
      _call<void>('updateRadarKeywords', {'keywords': keywords});

  /// Test-only: pushes a post into [radarPosts] as if the native service had
  /// observed it. Never called in production code.
  @visibleForTesting
  static void debugEmitRadarPost(String text, {String? author}) {
    final post = RadarPost(text: text, author: author);
    _radarPosts.add(post);
  }

  /// Pushes the Flutter-side pipeline counters (second filter, AI verdicts,
  /// saves) so the native status notification shows them in realtime.
  static Future<void> updateRadarStats(
    Map<String, int> stats, {
    String mode = 'score',
  }) => _call<void>('updateRadarStats', {'stats': stats, 'mode': mode});

  static Future<void> openEmail({
    required String to,
    required String subject,
    required String body,
    String? attachmentPath,
  }) => _call<void>('openEmail', {
    'to': to,
    'subject': subject,
    'body': body,
    'attachmentPath': attachmentPath,
  });
}

/// A post observed by the Android radar while the user scrolled LinkedIn.
class RadarPost {
  const RadarPost({required this.text, this.author});

  final String text;
  final String? author;

  static RadarPost? fromExtras(Map<String, Object?>? extras) {
    final text = (extras?['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    final author = (extras?['author'] as String?)?.trim();
    return RadarPost(
      text: text,
      author: (author == null || author.isEmpty) ? null : author,
    );
  }
}

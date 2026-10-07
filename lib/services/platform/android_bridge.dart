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
  static final _radarState = StreamController<RadarState>.broadcast();

  static Stream<CapturedPost> get sharedPosts => _sharedPosts.stream;
  static Stream<RadarPost> get radarPosts => _radarPosts.stream;

  /// Capture-state changes pushed by the native service. Emitted no matter
  /// where the change came from — the in-app control, the notification-shade
  /// action, or the system binding/unbinding the accessibility service.
  static Stream<RadarState> get radarState => _radarState.stream;

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
          case 'onRadarStateChanged':
            _radarState.add(RadarState.fromExtras(args));
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

  /// True when the user paused capture. The accessibility service is still
  /// enabled, so resuming needs no new permission.
  static Future<bool> isRadarPaused() async =>
      await _call<bool>('isRadarPaused') ?? false;

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

  /// Pushes the user's job preferences into the native radar so its first
  /// filter mirrors the Dart-side second filter exactly: with preferences
  /// set, a post must mention one of [roles] and (when [locations] is set)
  /// one of the locations to be forwarded at all.
  static Future<void> updateRadarKeywords({
    required List<String> roles,
    required List<String> locations,
  }) => _call<void>('updateRadarKeywords', {
    'roles': roles,
    'locations': locations,
  });

  /// Pauses the background radar. The accessibility service stays enabled, so
  /// [resumeRadar] starts capturing again without any permission prompt.
  static Future<void> pauseRadar() => _call<void>('pauseRadar');

  static Future<void> resumeRadar() => _call<void>('resumeRadar');

  /// Test-only: pushes a post into [radarPosts] as if the native service had
  /// observed it. Never called in production code.
  @visibleForTesting
  static void debugEmitRadarPost(
    String text, {
    String? author,
    String? headline,
    String kind = 'post',
  }) {
    final post = RadarPost(
      text: text,
      author: author,
      headline: headline,
      kind: kind,
    );
    _radarPosts.add(post);
  }

  /// Test-only: pushes a capture-state change into [radarState] as if the
  /// native service had made it (e.g. from the notification shade). Never
  /// called in production code.
  @visibleForTesting
  static void debugEmitRadarState({
    required bool enabled,
    required bool paused,
  }) {
    _radarState.add(RadarState(enabled: enabled, paused: paused));
  }

  /// Pushes the Flutter-side pipeline counters (second filter, AI verdicts,
  /// saves) so the native status notification shows them in realtime.
  static Future<void> updateRadarStats(
    Map<String, int> stats, {
    String mode = 'score',
  }) => _call<void>('updateRadarStats', {'stats': stats, 'mode': mode});

  /// Attaches the native radar push listener and drains posts the service
  /// buffered while no Flutter engine was listening. Call only after
  /// subscribing to [radarPosts]; until then the native side keeps
  /// buffering so nothing is lost.
  static Future<void> startRadarListener() async {
    if (kIsWeb) return;
    try {
      final pending = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'startRadarListener',
      );
      for (final raw in pending ?? const <Map<Object?, Object?>>[]) {
        final post = RadarPost.fromExtras(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (post != null) _radarPosts.add(post);
      }
    } on MissingPluginException {
      // Not on a device: nothing buffered.
    } on PlatformException {
      // Native side unavailable: the next post will still arrive via push.
    }
  }

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

/// A post (or poster-profile screen) observed by the Android radar while the
/// user scrolled LinkedIn.
class RadarPost {
  const RadarPost({
    required this.text,
    this.author,
    this.headline,
    this.kind = 'post',
  });

  final String text;

  /// Poster name, read from the post card header by the native service.
  final String? author;

  /// Poster headline rendered under their name ("Recruiter at Acme · 2nd").
  final String? headline;

  /// `post` for a feed post card; `profile` for the poster's profile screen.
  final String kind;

  static RadarPost? fromExtras(Map<String, Object?>? extras) {
    final text = (extras?['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    String? readNonEmpty(String key) {
      final value = (extras?[key] as String?)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    return RadarPost(
      text: text,
      author: readNonEmpty('author'),
      headline: readNonEmpty('headline'),
      kind: readNonEmpty('kind') == 'profile' ? 'profile' : 'post',
    );
  }
}

/// The native radar's capture state at the moment it changed. Carried as a
/// wake-up signal: pages re-read the authoritative values over the channel
/// rather than trusting a copy that could already be stale.
class RadarState {
  const RadarState({required this.enabled, required this.paused});

  /// The accessibility service is bound and allowed to read LinkedIn.
  final bool enabled;

  /// The user asked to stop capturing. Access is kept, so resuming is one tap.
  final bool paused;

  static RadarState fromExtras(Map<String, Object?>? extras) => RadarState(
    enabled: extras?['enabled'] == true,
    paused: extras?['paused'] == true,
  );
}

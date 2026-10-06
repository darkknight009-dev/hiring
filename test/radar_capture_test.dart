import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/app_dependencies.dart';
import 'package:hiring/services/platform/android_bridge.dart';
import 'package:hiring/services/radar/radar_capture.dart';
import 'package:hiring/services/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDependencies deps;
  late List<MethodCall> channelCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    deps = AppDependencies(prefs: prefs);
    channelCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.hiringradar/share'),
          (call) async {
            channelCalls.add(call);
            if (call.method == 'isRadarEnabled') return true;
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.hiringradar/share'),
          null,
        );
  });

  /// Emits a post into the native stream the capture listens to.
  void emit(String text) => AndroidBridge.debugEmitRadarPost(text);

  /// Waits until the capture queue has fully drained.
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  List<Map<Object?, Object?>> statsCalls() => channelCalls
      .where((c) => c.method == 'updateRadarStats')
      .map((c) => (c.arguments as Map)['stats'] as Map<Object?, Object?>)
      .toList();

  test('queue processes every post instead of dropping overlaps', () async {
    final capture = RadarCapture(deps)..start();

    // Three hiring posts emitted back-to-back while the first is still
    // processing: none may be dropped.
    emit(
      'We are hiring a React developer at Example Studio. DM me your resume.',
    );
    emit('We are hiring a Flutter engineer at Acme. Apply now.');
    emit(
      'We are hiring a designer at Beta. Send your resume to careers@beta.com.',
    );
    await settle();

    final all = await deps.repository.loadAll();
    expect(all, hasLength(3), reason: 'overlapping posts must queue, not drop');
    expect(all.every((o) => o.capturedVia == 'radar'), isTrue);
    expect(capture, isNotNull);
  });

  test('second-filter skips are counted and published to the shade', () async {
    final capture = RadarCapture(deps)..start();

    // Matches the offline hiring score filter…
    emit(
      'We are hiring a React developer at Example Studio. DM me your resume.',
    );
    // …this one scores below the default threshold of 4.
    emit(
      'Coffee with the team this afternoon was lovely. Great chat about life.',
    );
    await settle();

    final stats = statsCalls();
    expect(stats, isNotEmpty, reason: 'stats must be pushed to the shade');
    final last = stats.last;
    expect(last['matched'], 1);
    expect(last['skipped'], 1);
    expect(last['saved'], 1);
    expect(capture, isNotNull);
  });

  test('job preferences become the second filter when set', () async {
    SharedPreferences.setMockInitialValues({
      'prefs.roles': ['Flutter developer'],
    });
    final freshPrefs = await SharedPreferences.getInstance();
    final freshDeps = AppDependencies(prefs: freshPrefs);
    final capture = RadarCapture(freshDeps)..start();

    // Hiring keywords pass the native gate, but the role is not the one the
    // user asked for — the preference filter must skip it.
    emit(
      'We are hiring a React developer at Example Studio. DM me your resume.',
    );
    emit('Hiring a Flutter developer in Berlin. Apply now to join our team.');
    await settle();

    final stats = statsCalls();
    expect(stats, isNotEmpty);
    final last = stats.last;
    expect(last['matched'], 1);
    expect(last['skipped'], 1);
    expect(last['saved'], 1);

    final all = await freshDeps.repository.loadAll();
    expect(all, hasLength(1));
    expect(all.first.text, contains('Flutter developer'));
    expect(capture, isNotNull);
  });

  test('stats mode reflects whether preferences or score filtered', () async {
    final capture = RadarCapture(deps)..start();
    emit(
      'We are hiring a React developer at Example Studio. DM me your resume.',
    );
    await settle();

    final modes = channelCalls
        .where((c) => c.method == 'updateRadarStats')
        .map((c) => (c.arguments as Map)['mode'] as String)
        .toList();
    expect(modes, isNotEmpty);
    expect(modes.last, 'score'); // no preferences set in this store
    expect(capture, isNotNull);
  });

  test('duplicate posts are processed once', () async {
    final capture = RadarCapture(deps)..start();
    const text =
        'We are hiring a React developer at Example Studio. DM me your resume.';
    emit(text);
    emit(text);
    emit(text);
    await settle();

    final all = await deps.repository.loadAll();
    expect(all, hasLength(1));
    expect(capture, isNotNull);
  });

  test('radar keywords are synced from settings at start', () async {
    SharedPreferences.setMockInitialValues({
      'prefs.roles': ['Flutter developer', ''],
      'prefs.locations': ['Berlin'],
    });
    final freshPrefs = await SharedPreferences.getInstance();
    final freshDeps = AppDependencies(prefs: freshPrefs);
    RadarCapture(freshDeps).start();
    await settle();

    final keywordCalls = channelCalls
        .where((c) => c.method == 'updateRadarKeywords')
        .toList();
    expect(keywordCalls, isNotEmpty);
    final keywords =
        (keywordCalls.last.arguments as Map)['keywords'] as List<Object?>;
    expect(keywords, containsAll(['Flutter developer', 'Berlin']));
    // The store returns what was seeded; blank entries are only stripped on
    // write (via setPreferredRoles), and the native gate ignores blanks.
    expect(
      SettingsStore(prefs: freshPrefs).preferredRoles,
      contains('Flutter developer'),
    );
  });
}

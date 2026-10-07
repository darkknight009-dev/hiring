import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/app.dart';
import 'package:hiring/app_dependencies.dart';
import 'package:hiring/core/theme/app_theme.dart';
import 'package:hiring/features/analyze/analyze_page.dart';
import 'package:hiring/models/captured_post.dart';
import 'package:hiring/models/opportunity.dart';
import 'package:hiring/models/outreach.dart';
import 'package:hiring/services/analysis/ai_provider.dart';
import 'package:hiring/services/capture/capture_provider.dart';
import 'package:hiring/services/platform/android_bridge.dart';
import 'package:hiring/services/radar/radar_capture.dart';
import 'package:hiring/widgets/splash_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppDependencies> makeDeps({
  Map<String, Object> values = const {},
}) async {
  // Existing tests exercise the main workspace, not first launch.
  SharedPreferences.setMockInitialValues({'onboarding.done': true, ...values});
  final prefs = await SharedPreferences.getInstance();
  // AI is built in with a real key; tests must never hit the network.
  return AppDependencies(prefs: prefs, aiOverride: _FakeAi());
}

Widget wrap(Widget child, AppDependencies deps) =>
    AppDependenciesScope(deps: deps, child: child);

Future<void> openCapture(WidgetTester tester) async {
  // The launch splash is finite, so settling always lands on the workspace.
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Analyze LinkedIn Post'));
  await tester.tap(find.text('Analyze LinkedIn Post'));
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Analyze post');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('launch plays the radar splash before the workspace', (
    tester,
  ) async {
    setViewport(tester, const Size(390, 844));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.pump();
    expect(find.byKey(const Key('splash-wordmark')), findsOneWidget);
    expect(find.text('Never miss a hiring post.'), findsNothing);

    await tester.pump(SplashPage.duration);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('splash-wordmark')), findsNothing);
    expect(find.text('Never miss a hiring post.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('dashboard and capture fit ${size.width.toInt()}px', (
      tester,
    ) async {
      setViewport(tester, size);
      final deps = await makeDeps();
      await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
      await tester.pumpAndSettle();
      expect(find.text('Never miss a hiring post.'), findsOneWidget);
      expect(find.text('Recent Opportunities'), findsOneWidget);
      expect(
        find.byType(NavigationBar),
        size.width < 900 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await openCapture(tester);
      expect(find.text('Analyze LinkedIn Opportunity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small screen supports large text without overflow', (
    tester,
  ) async {
    setViewport(tester, const Size(320, 900));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Analyze LinkedIn Post'));
    await openCapture(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme toggles light and dark', (tester) async {
    setViewport(tester, const Size(1440, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Switch to light mode'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
  });

  testWidgets('empty input and invalid URL are explained', (tester) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await openCapture(tester);
    await preview(tester);
    expect(
      find.text('Paste a LinkedIn post URL or some post text to continue.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('post-url')),
      'https://example.com/post',
    );
    await preview(tester);
    expect(
      find.textContaining('Use a valid HTTPS LinkedIn post URL'),
      findsOneWidget,
    );
    expect(find.text('Save to my inbox'), findsNothing);
  });

  testWidgets('URL only never claims retrieval or analysis', (tester) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-url')),
      'https://www.linkedin.com/posts/fictional_hiring-123',
    );
    await preview(tester);
    expect(find.text('Capture preview · not analyzed'), findsOneWidget);
    expect(
      find.textContaining(
        'Add the post text so the offline filter and AI can read it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hiring post saves an opportunity and dashboard counts update', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-text')),
      "We are hiring a Senior Flutter engineer at Example Studio in Berlin. DM me your resume to apply.",
    );
    await preview(tester);
    // The built-in AI (faked here) analyzes every hiring-looking post.
    expect(find.text('Analysis result'), findsOneWidget);
    expect(find.textContaining('Analyzed with fake-model'), findsOneWidget);
    await tester.ensureVisible(find.text('Save to my inbox'));
    await tester.tap(find.text('Save to my inbox'));
    await tester.pumpAndSettle();
    final saved = await deps.repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.analysis.isHiring, isTrue);
    expect(saved.first.analysis.role, 'Flutter Engineer');
    expect(saved.first.text, contains('We are hiring'));

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('non-hiring post skips AI and reports the filter decision', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-text')),
      'Thinking about family, coffee and sunsets today.',
    );
    await preview(tester);
    expect(
      find.textContaining('offline filter found no hiring signals'),
      findsOneWidget,
    );
    expect(find.text('Save to my inbox'), findsOneWidget);
  });

  testWidgets('AI analysis shows extracted result and saves it', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-text')),
      "We are hiring a React developer at Example Studio. DM me your resume.",
    );
    await preview(tester);
    expect(find.text('Analysis result'), findsOneWidget);
    expect(find.text('EXTRACTED DETAILS'), findsOneWidget);
    expect(find.text('Looks like a hiring post'), findsOneWidget);
    expect(find.text('Flutter Engineer'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Save to my inbox'), findsOneWidget);
    await tester.ensureVisible(find.text('Save to my inbox'));
    await tester.tap(find.text('Save to my inbox'));
    await tester.pumpAndSettle();
    final saved = await deps.repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.analysis.isHiring, isTrue);
    expect(saved.first.analysis.company, 'Acme');
  });

  testWidgets('first launch shows onboarding and preferences reach the radar', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps(values: {'onboarding.done': false});
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.pumpAndSettle();

    // Step 1: welcome.
    expect(find.text('FeedRadar'), findsWidgets);
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Step 2: profile. The forward button stays disabled until a name is
    // entered, so let the validation rebuild land before tapping.
    expect(find.text('Add your name to continue.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Test User');
    await tester.pump();
    expect(find.text('Add your name to continue.'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step 3: preferences. Blocked until at least one keyword exists.
    expect(
      find.text(
        'Add at least one role or location so your radar knows what to catch.',
      ),
      findsOneWidget,
    );
    final rolesField = find.descendant(
      of: find.byKey(const Key('keyword-field-Roles or keywords')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(rolesField, 'Flutter developer,');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Add at least one role or location so your radar knows what to catch.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Tune my radar'));
    await tester.pump(); // finishing state with the radar loader
    expect(find.text('Tuning your radar…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100)); // finish delay
    await tester.pump(const Duration(milliseconds: 600)); // switcher
    expect(find.text('Tuning your radar…'), findsNothing);
    expect(find.text('Never miss a hiring post.'), findsOneWidget);
    expect(deps.settings.onboarded, isTrue);
    expect(deps.settings.profileName, 'Test User');
    expect(deps.settings.preferredRoles, contains('Flutter developer'));
  });

  testWidgets('pending capture prevents double submit and shows real failure', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final provider = _PendingCapture();
    final deps = await makeDeps();
    await tester.pumpWidget(
      wrap(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AnalyzePage(deps: deps, captureProvider: provider),
          ),
        ),
        deps,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('post-text')),
      'Keep this draft.',
    );
    await tester.tap(find.text('Analyze post'));
    await tester.pump();
    expect(find.text('Capturing input…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    provider.result.completeError(StateError('Simulated platform failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not capture this post.'), findsOneWidget);
    expect(find.text('Keep this draft.'), findsOneWidget);
    expect(find.text('Analyze post'), findsOneWidget);
  });

  testWidgets('dashboard radar card shows status and radar capture count', (
    tester,
  ) async {
    setViewport(tester, const Size(390, 1600));
    final now = DateTime.now().toUtc().toIso8601String();
    final deps = await makeDeps(
      values: {
        'opportunities.v1': jsonEncode([
          {
            'id': 'radar-1',
            'createdAt': now,
            'updatedAt': now,
            'status': 'new',
            'analysis': {
              'isHiring': true,
              'role': 'Flutter Engineer',
              'company': 'Acme',
            },
            'text': 'We are hiring a Flutter Engineer at Acme!',
            'capturedVia': 'radar',
            'connectionState': 'none',
            'drafts': {},
          },
        ]),
      },
    );
    // The dashboard queries the native radar over the platform channel.
    // Mock it so the status resolves (an unmocked channel future never
    // completes in tests) and assert the ON state deterministically.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.hiringradar/share'),
          (call) async {
            if (call.method == 'isRadarEnabled') return true;
            return null;
          },
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.hiringradar/share'),
            null,
          );
    });
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('radar-status-card')), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.text('1 post captured so far.'), findsOneWidget);
    expect(find.text('See captures'), findsOneWidget);
    // Radar is on, so the enable CTA is hidden.
    expect(find.byKey(const Key('radar-enable-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capture stops and resumes in-app without asking for permission again',
    (tester) async {
      setViewport(tester, const Size(390, 1600));
      final deps = await makeDeps();
      var paused = false;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.hiringradar/share'),
            (call) async {
              calls.add(call.method);
              switch (call.method) {
                case 'isRadarEnabled':
                  return true;
                case 'isRadarPaused':
                  return paused;
                case 'pauseRadar':
                  paused = true;
                  return null;
                case 'resumeRadar':
                  paused = false;
                  return null;
              }
              return null;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('app.hiringradar/share'),
              null,
            );
      });

      await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
      await tester.pumpAndSettle();
      expect(find.text('ON'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('radar-stop-button')));
      await tester.tap(find.byKey(const Key('radar-stop-button')));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsOneWidget);
      expect(calls, contains('pauseRadar'));
      // Stopping keeps the accessibility grant, so it never routes the user
      // through system settings.
      expect(calls, isNot(contains('openAccessibilitySettings')));

      await tester.ensureVisible(find.byKey(const Key('radar-resume-button')));
      await tester.tap(find.byKey(const Key('radar-resume-button')));
      await tester.pumpAndSettle();
      expect(find.text('ON'), findsOneWidget);
      expect(calls, contains('resumeRadar'));
      expect(calls, isNot(contains('openAccessibilitySettings')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a capture toggle made outside the app still updates the screen',
    (tester) async {
      setViewport(tester, const Size(390, 1600));
      final deps = await makeDeps();
      var paused = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.hiringradar/share'),
            (call) async {
              switch (call.method) {
                case 'isRadarEnabled':
                  return true;
                case 'isRadarPaused':
                  return paused;
              }
              return null;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('app.hiringradar/share'),
              null,
            );
      });
      // Mirrors main.dart: the pipeline owns the native-to-UI relay.
      RadarCapture(deps).start();

      await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
      await tester.pumpAndSettle();
      expect(find.text('ON'), findsOneWidget);

      // The user taps "Stop capture" in the notification shade. Nothing in the
      // widget tree is touched: native pushes the change and the screen must
      // follow, otherwise it keeps claiming capture is on.
      paused = true;
      AndroidBridge.debugEmitRadarState(enabled: true, paused: true);
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('ON'), findsNothing);

      // Resuming from the shade syncs back the same way.
      paused = false;
      AndroidBridge.debugEmitRadarState(enabled: true, paused: false);
      await tester.pumpAndSettle();
      expect(find.text('ON'), findsOneWidget);
      expect(find.text('PAUSED'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'share arriving while the app is open lands in the capture form',
    (tester) async {
      setViewport(tester, const Size(390, 844));
      final deps = await makeDeps();
      await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
      await tester.pumpAndSettle();

      // Simulate the platform share sheet delivering a post mid-session; the
      // capture page is already mounted, so this must reach it via listeners.
      await deps.setPendingCapture(
        CapturedPost.fromInput(text: 'We are hiring a Flutter dev at Acme!'),
      );
      await tester.pumpAndSettle();

      // The shell switched to the capture tab and the form carries the text.
      expect(find.text('Analyze LinkedIn Opportunity'), findsOneWidget);
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('post-text')),
      );
      expect(field.controller!.text, 'We are hiring a Flutter dev at Acme!');
    },
  );
}

class _PendingCapture implements CaptureProvider {
  final result = Completer<CapturedPost?>();

  @override
  Future<CapturedPost?> capturePost() => result.future;
}

/// Deterministic stand-in for the built-in NVIDIA provider so widget tests
/// never make network calls with the embedded key.
class _FakeAi implements AiProvider {
  @override
  Future<AnalysisResult> analyzePost({required String text, Uri? url}) async =>
      AnalysisResult(
        analysis: const PostAnalysis(
          isHiring: true,
          confidence: 90,
          role: 'Flutter Engineer',
          company: 'Acme',
          summary: 'Fake analysis.',
        ),
        modelUsed: 'fake-model',
      );

  @override
  Future<OutreachDraft> generateDraft({
    required String kind,
    required String postText,
    String? posterName,
    String? role,
    String? company,
    required UserProfile profile,
  }) async => OutreachDraft(
    kind: kind,
    subject: 'Fake subject',
    body: 'Fake draft body.',
    createdAt: DateTime.now().toUtc(),
  );
}

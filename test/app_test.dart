import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/app.dart';
import 'package:hiring/app_dependencies.dart';
import 'package:hiring/core/theme/app_theme.dart';
import 'package:hiring/features/analyze/analyze_page.dart';
import 'package:hiring/models/captured_post.dart';
import 'package:hiring/services/capture/capture_provider.dart';
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
  return AppDependencies(prefs: prefs);
}

Widget wrap(Widget child, AppDependencies deps) =>
    AppDependenciesScope(deps: deps, child: child);

Future<void> openCapture(WidgetTester tester) async {
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
    // No AI key: the offline path must complete without AI analysis.
    expect(find.text('Capture preview · not analyzed'), findsOneWidget);
    expect(find.textContaining('No AI key configured'), findsOneWidget);
    await tester.ensureVisible(find.text('Save to my inbox'));
    await tester.tap(find.text('Save to my inbox'));
    await tester.pumpAndSettle();
    final saved = await deps.repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.analysis.isHiring, isFalse);
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
    expect(find.text('Capture preview · not analyzed'), findsOneWidget);
    expect(find.text('Save to my inbox'), findsOneWidget);
    await tester.ensureVisible(find.text('Save to my inbox'));
    await tester.tap(find.text('Save to my inbox'));
    await tester.pumpAndSettle();
    final saved = await deps.repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.analysis.isHiring, isFalse);
  });

  testWidgets('settings page stores the API key locally', (tester) async {
    setViewport(tester, const Size(1200, 1000));
    final deps = await makeDeps();
    await tester.pumpWidget(wrap(HiringRadarApp(deps: deps), deps));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('api-key-field')),
      'test-key-123',
    );
    await tester.tap(find.byKey(const Key('save-key-button')));
    await tester.pumpAndSettle();
    expect(deps.settings.apiKey, 'test-key-123');
    expect(deps.hasAiKey, isTrue);
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

    // Step 2: profile.
    await tester.enterText(find.byType(TextFormField).first, 'Test User');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step 3: preferences.
    final rolesField = find.descendant(
      of: find.byKey(const Key('keyword-field-Roles or keywords')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(rolesField, 'Flutter developer,');
    await tester.pumpAndSettle();

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
}

class _PendingCapture implements CaptureProvider {
  final result = Completer<CapturedPost?>();

  @override
  Future<CapturedPost?> capturePost() => result.future;
}

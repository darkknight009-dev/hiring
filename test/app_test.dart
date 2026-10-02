import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring/app.dart';
import 'package:hiring/core/theme/app_theme.dart';
import 'package:hiring/features/analyze/analyze_page.dart';
import 'package:hiring/models/captured_post.dart';
import 'package:hiring/services/capture/capture_provider.dart';

void setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> openCapture(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Analyze LinkedIn Post'));
  await tester.tap(find.text('Analyze LinkedIn Post'));
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester) async {
  final button = find.text('Preview capture');
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
      await tester.pumpWidget(const HiringRadarApp());
      await tester.pumpAndSettle();
      expect(find.text('Never miss a hiring post.'), findsOneWidget);
      expect(find.text('Recent Opportunities'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
      expect(
        find.byType(NavigationBar),
        size.width < 900 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await openCapture(tester);
      expect(find.text('Analyze LinkedIn Opportunity'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('post-text')),
        'We are hiring a React developer.',
      );
      await preview(tester);
      expect(find.byKey(const Key('capture-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small screen supports large text without overflow', (
    tester,
  ) async {
    setViewport(tester, const Size(320, 900));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const HiringRadarApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Analyze LinkedIn Post'));
    await openCapture(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme toggles light and dark', (tester) async {
    setViewport(tester, const Size(1440, 1000));
    await tester.pumpWidget(const HiringRadarApp());
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
    await tester.pumpWidget(const HiringRadarApp());
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
    expect(find.byKey(const Key('capture-preview')), findsNothing);
  });

  testWidgets('URL only never claims retrieval or analysis', (tester) async {
    setViewport(tester, const Size(1200, 1000));
    await tester.pumpWidget(const HiringRadarApp());
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-url')),
      'https://www.linkedin.com/posts/fictional_hiring-123',
    );
    await preview(tester);
    expect(find.text('Capture preview · not analyzed'), findsOneWidget);
    expect(
      find.textContaining('We haven’t retrieved this URL.'),
      findsOneWidget,
    );
  });

  testWidgets('draft survives navigation; editing invalidates stale preview', (
    tester,
  ) async {
    setViewport(tester, const Size(1440, 1000));
    await tester.pumpWidget(const HiringRadarApp());
    await openCapture(tester);
    await tester.enterText(
      find.byKey(const Key('post-text')),
      'We are hiring.',
    );
    await preview(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Overview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-preview')), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Analyze post'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture-preview')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('post-text')));
    await tester.enterText(
      find.byKey(const Key('post-text')),
      'Different content',
    );
    await tester.pump();
    expect(find.byKey(const Key('capture-preview')), findsNothing);
  });

  testWidgets('pending capture prevents double submit and shows real failure', (
    tester,
  ) async {
    setViewport(tester, const Size(1200, 1000));
    final provider = _PendingCapture();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AnalyzePage(captureProvider: provider)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('post-text')),
      'Keep this draft.',
    );
    await tester.tap(find.text('Preview capture'));
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
    expect(find.text('Preview capture'), findsOneWidget);
  });
}

class _PendingCapture implements CaptureProvider {
  final result = Completer<CapturedPost?>();

  @override
  Future<CapturedPost?> capturePost() => result.future;
}

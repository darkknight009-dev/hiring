import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_page.dart';
import 'widgets/app_shell.dart';

class HiringRadarApp extends StatefulWidget {
  const HiringRadarApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<HiringRadarApp> createState() => _HiringRadarAppState();
}

class _HiringRadarAppState extends State<HiringRadarApp> {
  ThemeMode _themeMode = ThemeMode.system;
  late bool _onboarded = widget.deps.settings.onboarded;

  void _toggleTheme() {
    final dark =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    setState(() => _themeMode = dark ? ThemeMode.light : ThemeMode.dark);
  }

  void _completeOnboarding() {
    if (!mounted) return;
    setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FeedRadar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _onboarded
            ? KeyedSubtree(
                key: const ValueKey('app-shell'),
                child: AppShell(onToggleTheme: _toggleTheme, deps: widget.deps),
              )
            : KeyedSubtree(
                key: const ValueKey('onboarding'),
                child: OnboardingPage(
                  deps: widget.deps,
                  onFinished: _completeOnboarding,
                ),
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'core/theme/app_theme.dart';
import 'widgets/app_shell.dart';

class HiringRadarApp extends StatefulWidget {
  const HiringRadarApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<HiringRadarApp> createState() => _HiringRadarAppState();
}

class _HiringRadarAppState extends State<HiringRadarApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    final dark =
        _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    setState(() => _themeMode = dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hiring Radar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AppShell(onToggleTheme: _toggleTheme, deps: widget.deps),
    );
  }
}

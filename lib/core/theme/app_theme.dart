import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double page = 40;
  static const double radius = 12;
  static const double desktopBreakpoint = 900;
  static const double contentWidth = 1120;
}

abstract final class AppTheme {
  static const _green = Color(0xFF24734F);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _green,
      brightness: brightness,
      primary: dark ? const Color(0xFF8ED6AE) : _green,
      surface: dark ? const Color(0xFF191D1B) : Colors.white,
      onSurface: dark ? const Color(0xFFE8ECE9) : const Color(0xFF202C25),
      onSurfaceVariant: dark
          ? const Color(0xFFAAB7AE)
          : const Color(0xFF647168),
      outlineVariant: dark
          ? const Color(0xFF333D36)
          : const Color(0xFFE3E8E3),
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: dark
          ? const Color(0xFF121613)
          : const Color(0xFFF7F8F5),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 38,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
          height: 1.15,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 19,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.6),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorMaxLines: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    );
  }
}

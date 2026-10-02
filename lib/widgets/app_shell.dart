import 'package:flutter/material.dart';

import '../core/routing/app_destination.dart';
import '../core/theme/app_theme.dart';
import '../features/analyze/analyze_page.dart';
import '../features/dashboard/dashboard_page.dart';
import 'radar_logo.dart';
import 'surface_card.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _destination = AppDestination.dashboard;

  void _navigate(AppDestination destination) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _destination = destination);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final desktop = MediaQuery.sizeOf(context).width >= AppSpacing.desktopBreakpoint;
    final themeButton = IconButton(
      tooltip: theme.brightness == Brightness.dark
          ? 'Switch to light mode'
          : 'Switch to dark mode',
      onPressed: widget.onToggleTheme,
      icon: Icon(
        theme.brightness == Brightness.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        size: 20,
      ),
    );

    final content = Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: desktop ? AppSpacing.page : 20, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              if (!desktop) ...[
                const RadarLogo(size: 30),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  desktop ? _destination.label : 'Hiring Radar',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (desktop)
                Text('Your next move starts here.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(width: 16),
              themeButton,
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _destination.index,
            children: [
              DashboardPage(onAnalyze: () => _navigate(AppDestination.analyze)),
              const AnalyzePage(),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: desktop,
        child: Row(
          children: [
            if (desktop)
              Container(
                width: 240,
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(right: BorderSide(color: colors.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 20, 36),
                      child: Row(
                        children: [
                          const RadarLogo(),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Hiring Radar', style: theme.textTheme.titleLarge)),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(26, 0, 24, 12),
                      child: SectionLabel('Workspace'),
                    ),
                    for (final destination in AppDestination.values)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          selected: _destination == destination,
                          selectedColor: colors.primary,
                          selectedTileColor: colors.primary.withValues(alpha: 0.08),
                          leading: Icon(destination.icon, size: 21),
                          title: Text(destination.label, style: theme.textTheme.labelLarge),
                          onTap: () => _navigate(destination),
                        ),
                      ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Notice(
                        icon: Icons.shield_outlined,
                        text: 'Your radar. Your decisions.\nNothing is sent on your behalf.',
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('WEB PREVIEW  /  0.1', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 1)),
                    ),
                  ],
                ),
              ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _destination.index,
              onDestinationSelected: (index) => _navigate(AppDestination.values[index]),
              destinations: [
                for (final destination in AppDestination.values)
                  NavigationDestination(icon: Icon(destination.icon), label: destination.label),
              ],
            ),
    );
  }
}

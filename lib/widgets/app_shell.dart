import 'package:flutter/material.dart';

import '../app_dependencies.dart';
import '../core/routing/app_destination.dart';
import '../core/theme/app_theme.dart';
import '../features/analyze/analyze_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/opportunities/opportunities_page.dart';
import '../features/settings/settings_page.dart';
import 'radar_logo.dart';
import 'surface_card.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onToggleTheme, required this.deps});

  final VoidCallback onToggleTheme;
  final AppDependencies deps;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _destination = AppDestination.dashboard;

  @override
  void initState() {
    super.initState();
    widget.deps.addListener(_onDepsChanged);
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deps != widget.deps) {
      oldWidget.deps.removeListener(_onDepsChanged);
      widget.deps.addListener(_onDepsChanged);
    }
  }

  @override
  void dispose() {
    widget.deps.removeListener(_onDepsChanged);
    super.dispose();
  }

  void _onDepsChanged() {
    if (!mounted) return;
    if (widget.deps.hasPendingCapture &&
        _destination != AppDestination.analyze) {
      setState(() => _destination = AppDestination.analyze);
    }
  }

  void _navigate(AppDestination destination) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _destination = destination);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final desktop =
        MediaQuery.sizeOf(context).width >= AppSpacing.desktopBreakpoint;
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

    final pages = [
      DashboardPage(
        deps: widget.deps,
        onAnalyze: () => _navigate(AppDestination.analyze),
        onOpenOpportunities: () => _navigate(AppDestination.opportunities),
      ),
      OpportunitiesPage(deps: widget.deps),
      AnalyzePage(deps: widget.deps),
      SettingsPage(deps: widget.deps),
    ];

    final content = Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? AppSpacing.page : 20,
            vertical: 12,
          ),
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
                  desktop ? _destination.label : 'FeedRadar',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (desktop)
                Text(
                  'Your next move starts here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 16),
              themeButton,
            ],
          ),
        ),
        Expanded(
          child: _AnimatedIndexedStack(
            index: _destination.index,
            children: pages,
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
                  border: Border(
                    right: BorderSide(color: colors.outlineVariant),
                  ),
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
                          Expanded(
                            child: Text(
                              'FeedRadar',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
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
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            selected: _destination == destination,
                            selectedColor: colors.primary,
                            selectedTileColor: colors.primary.withValues(
                              alpha: 0.08,
                            ),
                            leading: Icon(destination.icon, size: 21),
                            title: Text(
                              destination.label,
                              style: theme.textTheme.labelLarge,
                            ),
                            onTap: () => _navigate(destination),
                          ),
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
                      child: Text(
                        'FEEDRADAR  ·  0.4',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          letterSpacing: 1,
                        ),
                      ),
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
              onDestinationSelected: (index) =>
                  _navigate(AppDestination.values[index]),
              destinations: [
                for (final destination in AppDestination.values)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }
}

/// An [IndexedStack] that reveals the newly selected page with a short fade
/// and slide. The stack keeps every page's state, so in-progress forms and
/// scroll positions survive tab switches.
class _AnimatedIndexedStack extends StatelessWidget {
  const _AnimatedIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        _PageReveal(active: i == index, child: children[i]),
    ],
  );
}

class _PageReveal extends StatefulWidget {
  const _PageReveal({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_PageReveal> createState() => _PageRevealState();
}

class _PageRevealState extends State<_PageReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      // A soft entrance for the first page on app launch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(_PageReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    } else if (!widget.active && oldWidget.active) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _offset, child: widget.child),
  );
}

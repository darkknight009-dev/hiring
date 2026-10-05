import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_dependencies.dart';
import '../../core/theme/app_theme.dart';
import '../../services/platform/android_bridge.dart';
import '../../widgets/keyword_field.dart';
import '../../widgets/radar_loader.dart';
import '../../widgets/radar_logo.dart';
import '../../widgets/surface_card.dart';

/// First-launch flow: who you are and which jobs your radar should catch.
/// The preferences are saved to Settings and pushed into the radar, so only
/// matching posts are captured. Everything is editable later in Settings.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.deps,
    required this.onFinished,
  });

  final AppDependencies deps;
  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Step { welcome, profile, preferences }

class _OnboardingPageState extends State<OnboardingPage> {
  final _nameController = TextEditingController();
  final _headlineController = TextEditingController();

  List<String> _roles = const [];
  List<String> _locations = const [];

  _Step _step = _Step.welcome;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _roles = [...widget.deps.settings.preferredRoles];
    _locations = [...widget.deps.settings.preferredLocations];
    _nameController.text = widget.deps.settings.profileName;
    _headlineController.text = widget.deps.settings.profileHeadline;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _headlineController.dispose();
    super.dispose();
  }

  void _goTo(_Step step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final settings = widget.deps.settings;
    await settings.setProfileName(_nameController.text);
    await settings.setProfileHeadline(_headlineController.text);
    await settings.setPreferredRoles(_roles);
    await settings.setPreferredLocations(_locations);
    await settings.setOnboarded(true);
    // Best-effort native push; the Dart-side preference filter is the
    // authoritative gate, so this never blocks onboarding.
    unawaited(AndroidBridge.updateRadarKeywords([..._roles, ..._locations]));
    // Give the tuning animation a beat before landing in the app.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final wide =
        MediaQuery.sizeOf(context).width >= AppSpacing.desktopBreakpoint;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.contentWidth,
              ),
              child: Padding(
                padding: EdgeInsets.all(wide ? AppSpacing.page : 20),
                child: _finishing
                    ? _TuningPanel(roles: _roles)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          // Progress dots.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final step in _Step.values)
                                AnimatedContainer(
                                  key: ValueKey('dot-${step.name}'),
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: _step == step ? 26 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _step == step
                                        ? colors.primary
                                        : colors.outlineVariant,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.03),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: switch (_step) {
                                _Step.welcome => const SingleChildScrollView(
                                  key: ValueKey('step-welcome'),
                                  child: _WelcomeStep(),
                                ),
                                _Step.profile => _ProfileStep(
                                  key: const ValueKey('step-profile'),
                                  nameController: _nameController,
                                  headlineController: _headlineController,
                                ),
                                _Step.preferences => _PreferencesStep(
                                  key: const ValueKey('step-preferences'),
                                  roles: _roles,
                                  locations: _locations,
                                  onRolesChanged: (roles) =>
                                      setState(() => _roles = roles),
                                  onLocationsChanged: (locations) =>
                                      setState(() => _locations = locations),
                                ),
                              },
                            ),
                          ),
                          // Footer actions.
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  if (_step != _Step.welcome)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _goTo(_Step.values[_step.index - 1]),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Back'),
                                    ),
                                  const Spacer(),
                                  if (_step != _Step.preferences)
                                    FilledButton.icon(
                                      onPressed: () =>
                                          _goTo(_Step.values[_step.index + 1]),
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _step == _Step.welcome
                                            ? 'Get started'
                                            : 'Continue',
                                      ),
                                    )
                                  else
                                    FilledButton.icon(
                                      onPressed: _finish,
                                      icon: const Icon(
                                        Icons.radar_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Tune my radar'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Center(child: RadarLogo(size: 72)),
        const SizedBox(height: 24),
        Center(child: Text('FeedRadar', style: theme.textTheme.headlineLarge)),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Your feed has hiring posts. Your radar catches them.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 32),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bullet(
                icon: Icons.radar_rounded,
                title: 'A passive radar',
                body:
                    'While you scroll LinkedIn, the radar reads visible posts and '
                    'captures hiring ones into your inbox. Read-only — it never '
                    'clicks, types, or sends.',
              ),
              const SizedBox(height: 16),
              _Bullet(
                icon: Icons.auto_awesome_outlined,
                title: 'Your AI, your key',
                body:
                    'Your own Gemini or NVIDIA key analyzes posts and drafts '
                    'connection notes, messages, and emails. Keys stay on this device.',
              ),
              const SizedBox(height: 16),
              _Bullet(
                icon: Icons.touch_app_outlined,
                title: 'You always press send',
                body:
                    'FeedRadar prepares ready-made outreach. Copy it, open your '
                    'apps, and send it yourself. Nothing is automated.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    super.key,
    required this.nameController,
    required this.headlineController,
  });

  final TextEditingController nameController;
  final TextEditingController headlineController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Step 2 of 3 · About you'),
          const SizedBox(height: 14),
          Text('Who is applying?', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Used only to personalize your outreach drafts. You can change '
            'this later in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 21),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: headlineController,
            decoration: const InputDecoration(
              labelText: 'Headline (optional)',
              hintText: 'e.g. Final-year CS student, Flutter developer',
              prefixIcon: Icon(Icons.badge_outlined, size: 21),
            ),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }
}

class _PreferencesStep extends StatelessWidget {
  const _PreferencesStep({
    super.key,
    required this.roles,
    required this.locations,
    required this.onRolesChanged,
    required this.onLocationsChanged,
  });

  final List<String> roles;
  final List<String> locations;
  final ValueChanged<List<String>> onRolesChanged;
  final ValueChanged<List<String>> onLocationsChanged;

  static const _roleSuggestions = [
    'Software engineer',
    'Flutter developer',
    'Data analyst',
    'Product designer',
    'Internship',
  ];
  static const _locationSuggestions = [
    'Remote',
    'Bengaluru',
    'Delhi NCR',
    'Mumbai',
    'Pune',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Step 3 of 3 · Job preferences'),
          const SizedBox(height: 14),
          Text(
            'What should your radar catch?',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Only posts mentioning your roles — and your locations, if you add '
            'them — are captured. Leave everything empty to capture all hiring '
            'posts. Change this anytime in Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          KeywordField(
            label: 'Roles or keywords',
            hint: 'e.g. Flutter developer, data analyst, UX designer',
            values: roles,
            onChanged: onRolesChanged,
            suggestions: _roleSuggestions,
          ),
          const SizedBox(height: 24),
          KeywordField(
            label: 'Locations (optional)',
            hint: 'e.g. Bengaluru, Remote',
            values: locations,
            onChanged: onLocationsChanged,
            suggestions: _locationSuggestions,
          ),
        ],
      ),
    );
  }
}

class _TuningPanel extends StatelessWidget {
  const _TuningPanel({required this.roles});

  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const RadarLoader(size: 96),
        const SizedBox(height: 28),
        Text('Tuning your radar…', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
          roles.isEmpty
              ? 'Scanning for every hiring post in your feed.'
              : 'Watching for: ${roles.take(4).join(', ')}${roles.length > 4 ? '…' : ''}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

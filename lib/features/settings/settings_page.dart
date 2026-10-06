import 'package:flutter/material.dart';

import '../../app_dependencies.dart';
import '../../services/platform/android_bridge.dart';
import '../../services/resume/resume_store.dart';
import '../../widgets/keyword_field.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

/// App settings. AI analysis is built in (NVIDIA NIM with an embedded key),
/// so there is no key management here.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nameController = TextEditingController();
  final _headlineController = TextEditingController();
  final _skillsController = TextEditingController();
  late List<String> _roles = [...widget.deps.settings.preferredRoles];
  late List<String> _locations = [...widget.deps.settings.preferredLocations];
  bool _radarEnabled = false;
  bool _radarPaused = false;
  bool _radarBusy = false;
  String? _resumePath;

  @override
  void initState() {
    super.initState();
    final settings = widget.deps.settings;
    _nameController.text = settings.profileName;
    _headlineController.text = settings.profileHeadline;
    _skillsController.text = settings.profileSkills;
    _resumePath = settings.resumePath;
    widget.deps.addListener(_onDepsChanged);
    _refreshRadarStatus();
  }

  /// Capture can be paused from the dashboard or the notification, so this
  /// page re-reads the native state whenever anything changes.
  void _onDepsChanged() {
    if (mounted) _refreshRadarStatus();
  }

  Future<void> _refreshRadarStatus() async {
    final status = await Future.wait([
      AndroidBridge.isRadarEnabled(),
      AndroidBridge.isRadarPaused(),
    ]);
    if (!mounted) return;
    setState(() {
      _radarEnabled = status[0];
      _radarPaused = status[1];
    });
  }

  @override
  void dispose() {
    widget.deps.removeListener(_onDepsChanged);
    _nameController.dispose();
    _headlineController.dispose();
    _skillsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final settings = widget.deps.settings;
    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Preferences'),
          const SizedBox(height: 14),
          Text('Settings', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
            'Your data stays on this device. AI analysis is built in — no keys, no setup.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI analysis', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Post analysis and outreach drafts are built in and run on NVIDIA NIM models. There is nothing to configure and no API key to manage.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                const Notice(
                  icon: Icons.shield_outlined,
                  text: 'Requests go directly from this device to NVIDIA. Your opportunities, profile, and resume never leave the device otherwise.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Offline filter', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Posts scoring below this many hiring signals skip AI analysis to save your quota.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        key: const Key('filter-threshold'),
                        value: settings.filterThreshold.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '${settings.filterThreshold}',
                        onChanged: (value) async {
                          await settings.setFilterThreshold(value.round());
                          setState(() {});
                        },
                      ),
                    ),
                    Text('${settings.filterThreshold}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Job preferences', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Your radar only captures posts matching these keywords. Leave both empty to capture every hiring post.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                KeywordField(
                  key: const Key('pref-roles'),
                  label: 'Roles or keywords',
                  hint: 'e.g. Flutter developer, data analyst',
                  values: _roles,
                  onChanged: (roles) {
                    setState(() => _roles = roles);
                    _saveJobPreferences();
                  },
                  suggestions: const [
                    'Software engineer',
                    'Flutter developer',
                    'Data analyst',
                    'Product designer',
                    'Internship',
                  ],
                ),
                const SizedBox(height: 20),
                KeywordField(
                  key: const Key('pref-locations'),
                  label: 'Locations (optional)',
                  hint: 'e.g. Bengaluru, Remote',
                  values: _locations,
                  onChanged: (locations) {
                    setState(() => _locations = locations);
                    _saveJobPreferences();
                  },
                  suggestions: const [
                    'Remote',
                    'Bengaluru',
                    'Delhi NCR',
                    'Mumbai',
                    'Pune',
                  ],
                ),
                const SizedBox(height: 12),
                const Notice(
                  icon: Icons.sync_rounded,
                  text: 'Synced with the background radar. New keywords start filtering right away.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Background radar (Android)',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    Icon(
                      _radarEnabled && !_radarPaused
                          ? Icons.radar_rounded
                          : Icons.radar_outlined,
                      color: _radarEnabled && !_radarPaused
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  !_radarEnabled
                      ? 'The radar reads visible LinkedIn posts while you scroll and captures hiring posts locally. Enable it in Accessibility settings.'
                      : _radarPaused
                      ? 'Paused. Stopping never revokes accessibility access, so resuming is one tap — no system settings, no new permission.'
                      : 'The radar is on. While you scroll LinkedIn, hiring posts are captured locally.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                const Notice(
                  icon: Icons.visibility_outlined,
                  text: 'Read-only: the radar never clicks, types, or sends. It only observes the LinkedIn app. You can disable it any time.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await AndroidBridge.requestNotificationPermission();
                        await AndroidBridge.openAccessibilitySettings();
                      },
                      icon: const Icon(
                        Icons.accessibility_new_rounded,
                        size: 18,
                      ),
                      label: const Text('Accessibility settings'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          AndroidBridge.requestNotificationPermission(),
                      child: const Text('Allow notifications'),
                    ),
                    if (_radarEnabled && _radarPaused)
                      FilledButton.tonalIcon(
                        key: const Key('resume-radar-button'),
                        onPressed: _radarBusy ? null : () => _setPaused(false),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Resume capture'),
                      )
                    else if (_radarEnabled)
                      OutlinedButton.icon(
                        key: const Key('stop-radar-button'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side: BorderSide(color: colors.error),
                        ),
                        onPressed: _radarBusy ? null : () => _setPaused(true),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Stop capture'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Reminder interval', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 4, label: Text('4 h')),
                    ButtonSegment(value: 12, label: Text('12 h')),
                    ButtonSegment(value: 24, label: Text('24 h')),
                    ButtonSegment(value: 48, label: Text('48 h')),
                  ],
                  selected: {settings.reminderHours},
                  onSelectionChanged: (selection) async {
                    await settings.setReminderHours(selection.first);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your profile', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Used only to personalize your drafts. Never invented beyond what you write here.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-name'),
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  onFieldSubmitted: (_) => _saveProfile(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-headline'),
                  controller: _headlineController,
                  decoration: const InputDecoration(
                    labelText: 'Headline',
                    hintText: 'e.g. Final-year CS student, Flutter developer',
                  ),
                  onFieldSubmitted: (_) => _saveProfile(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('profile-skills'),
                  controller: _skillsController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Skills and experience',
                    hintText: 'Facts the AI may use: projects, internships, stack, achievements…',
                    alignLabelWithHint: true,
                  ),
                  onFieldSubmitted: (_) => _saveProfile(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: settings.profileTone,
                  decoration: const InputDecoration(labelText: 'Draft tone'),
                  items: const [
                    DropdownMenuItem(
                      value: 'professional',
                      child: Text('Professional'),
                    ),
                    DropdownMenuItem(value: 'warm', child: Text('Warm')),
                    DropdownMenuItem(value: 'direct', child: Text('Direct')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await settings.setProfileTone(value);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save profile'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resume', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _resumePath == null
                      ? 'Pick a PDF once. It stays in app-private storage and is attached when you open an email draft in your email app.'
                      : 'Stored on this device: resume.pdf. It will be attached when you open an email draft.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final store = ResumeStore(settings);
                        final path = await store.pickAndStore();
                        if (!mounted) return;
                        setState(() => _resumePath = path ?? _resumePath);
                      },
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(
                        _resumePath == null ? 'Pick resume PDF' : 'Replace',
                      ),
                    ),
                    if (_resumePath != null)
                      OutlinedButton(
                        onPressed: () async {
                          final store = ResumeStore(settings);
                          await store.clear();
                          if (!mounted) return;
                          setState(() => _resumePath = null);
                        },
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Data on this device', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Opportunities and settings are stored locally. Deleting is permanent.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete all opportunities?'),
                        content: const Text(
                          'This removes every saved opportunity from this device. It cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete all'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final all = await widget.deps.repository.loadAll();
                    for (final opportunity in all) {
                      await widget.deps.repository.delete(opportunity.id);
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Delete all opportunities'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveJobPreferences() async {
    final settings = widget.deps.settings;
    await settings.setPreferredRoles(_roles);
    await settings.setPreferredLocations(_locations);
    await AndroidBridge.updateRadarKeywords(roles: _roles, locations: _locations);
  }

  /// Pauses or resumes capture. Pausing leaves the accessibility service
  /// enabled, so resuming is instant and never asks for permission again.
  Future<void> _setPaused(bool paused) async {
    setState(() => _radarBusy = true);
    if (paused) {
      await AndroidBridge.pauseRadar();
    } else {
      await AndroidBridge.resumeRadar();
    }
    if (!mounted) return;
    setState(() => _radarBusy = false);
    // Every page shows radar state; this keeps them in sync.
    widget.deps.dataChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paused
              ? 'Capture stopped. One tap resumes it — no permission needed.'
              : 'Capture resumed. The radar is reading your feed again.',
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final settings = widget.deps.settings;
    await settings.setProfileName(_nameController.text);
    await settings.setProfileHeadline(_headlineController.text);
    await settings.setProfileSkills(_skillsController.text);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved. Drafts will use it.')),
    );
  }
}

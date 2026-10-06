import 'package:flutter/material.dart';

import '../../app_dependencies.dart';
import '../../services/platform/android_bridge.dart';
import '../../services/resume/resume_store.dart';
import '../../services/settings/settings_store.dart';
import '../../widgets/keyword_field.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

/// User-managed AI configuration. The API key never leaves the device except
/// in requests to the chosen provider.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _nameController = TextEditingController();
  final _headlineController = TextEditingController();
  final _skillsController = TextEditingController();
  late List<String> _roles = [...widget.deps.settings.preferredRoles];
  late List<String> _locations = [...widget.deps.settings.preferredLocations];
  bool _obscureKey = true;
  bool _radarEnabled = false;
  String? _resumePath;

  @override
  void initState() {
    super.initState();
    final settings = widget.deps.settings;
    _apiKeyController.text = settings.apiKey ?? '';
    _modelController.text = settings.model;
    _nameController.text = settings.profileName;
    _headlineController.text = settings.profileHeadline;
    _skillsController.text = settings.profileSkills;
    _resumePath = settings.resumePath;
    _refreshRadarStatus();
  }

  Future<void> _refreshRadarStatus() async {
    final enabled = await AndroidBridge.isRadarEnabled();
    if (mounted) setState(() => _radarEnabled = enabled);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
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
            'Your key stays on this device and is used only for your own analysis requests.',
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
                  switch (settings.provider) {
                    AiProviderKind.gemini => 'Get a free Gemini API key at aistudio.google.com/apikey and paste it below.',
                    AiProviderKind.nvidia => 'Get a free NVIDIA API key at build.nvidia.com and paste it below. Any chat model from their catalog works, e.g. meta/llama-3.3-70b-instruct.',
                    AiProviderKind.openRouter =>
                      'Bring an OpenRouter key from openrouter.ai/keys.',
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<AiProviderKind>(
                  initialValue: settings.provider,
                  decoration: const InputDecoration(
                    labelText: 'Provider',
                    prefixIcon: Icon(Icons.auto_awesome, size: 21),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AiProviderKind.gemini,
                      child: Text('Google Gemini (free tier)'),
                    ),
                    DropdownMenuItem(
                      value: AiProviderKind.nvidia,
                      child: Text('NVIDIA NIM (build.nvidia.com)'),
                    ),
                    DropdownMenuItem(
                      value: AiProviderKind.openRouter,
                      child: Text('OpenRouter (bring your own key)'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    await settings.setProvider(value);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('api-key-field'),
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    hintText: switch (settings.provider) {
                      AiProviderKind.gemini => 'AIza…',
                      AiProviderKind.nvidia => 'nvapi-…',
                      AiProviderKind.openRouter => 'sk-or-…',
                    },
                    prefixIcon: const Icon(Icons.key_rounded, size: 21),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  onFieldSubmitted: _saveKey,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('model-field'),
                  controller: _modelController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Model (optional)',
                    hintText: switch (settings.provider) {
                      AiProviderKind.gemini => 'gemini-2.0-flash',
                      AiProviderKind.nvidia => 'meta/llama-3.3-70b-instruct',
                      AiProviderKind.openRouter => 'openrouter/model-id',
                    },
                    helperText:
                        'Leave empty to use the provider\'s default model.',
                    prefixIcon: const Icon(Icons.memory_rounded, size: 21),
                  ),
                  onFieldSubmitted: _saveModel,
                ),
                const SizedBox(height: 16),
                Wrap(
                  children: [
                    FilledButton.icon(
                      key: const Key('save-key-button'),
                      onPressed: () => _saveKey(_apiKeyController.text),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save key'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      key: const Key('save-model-button'),
                      onPressed: () => _saveModel(_modelController.text),
                      child: const Text('Save model'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        _apiKeyController.clear();
                        await _saveKey('');
                      },
                      child: const Text('Remove key'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Notice(
                  icon: Icons.shield_outlined,
                  text: widget.deps.hasAiKey
                      ? 'A key is stored on this device. Requests go directly to ${switch (settings.provider) {
                          AiProviderKind.gemini => 'Google',
                          AiProviderKind.nvidia => 'NVIDIA',
                          AiProviderKind.openRouter => 'OpenRouter',
                        }} from your browser or app.'
                      : 'No key stored yet. Analysis will run with the offline filter only.',
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
                      _radarEnabled
                          ? Icons.radar_rounded
                          : Icons.radar_outlined,
                      color: _radarEnabled
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _radarEnabled
                      ? 'The radar is on. While you scroll LinkedIn, hiring posts are captured locally.'
                      : 'The radar reads visible LinkedIn posts while you scroll and captures hiring posts locally. Enable it in Accessibility settings.',
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

  Future<void> _saveModel(String value) async {
    await widget.deps.settings.setModel(value.trim());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model saved. New requests use it.')),
    );
  }

  Future<void> _saveJobPreferences() async {
    final settings = widget.deps.settings;
    await settings.setPreferredRoles(_roles);
    await settings.setPreferredLocations(_locations);
    await AndroidBridge.updateRadarKeywords([..._roles, ..._locations]);
  }

  Future<void> _saveKey(String value) async {
    await widget.deps.settings.setApiKey(value.trim());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value.trim().isEmpty
              ? 'API key removed.'
              : 'API key saved on this device.',
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

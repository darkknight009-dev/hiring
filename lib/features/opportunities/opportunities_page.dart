import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_dependencies.dart';
import '../../models/opportunity_entity.dart';
import '../../models/outreach.dart';
import '../../services/analysis/ai_provider.dart';
import '../../services/outreach/outreach_service.dart';
import '../../services/platform/android_bridge.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

/// The saved inbox. Every action is explicit and local; nothing leaves the
/// device and nothing is sent on the user's behalf.
class OpportunitiesPage extends StatefulWidget {
  const OpportunitiesPage({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<OpportunitiesPage> createState() => _OpportunitiesPageState();
}

class _OpportunitiesPageState extends State<OpportunitiesPage> {
  String _query = '';
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Your inbox'),
          const SizedBox(height: 14),
          Text('Opportunities', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
            'Everything you captured, in one place. You decide what happens next.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('opportunity-search'),
                  initialValue: _query,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    labelText: 'Search',
                    hintText: 'Role, company, or text…',
                    prefixIcon: Icon(Icons.search_rounded, size: 21),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownMenu<String>(
                key: const Key('opportunity-status-filter'),
                initialSelection: _statusFilter,
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: '', label: 'All statuses'),
                  for (final status in Opportunity.statuses)
                    DropdownMenuEntry(
                      value: status,
                      label: _statusLabel(status),
                    ),
                ],
                onSelected: (value) => setState(
                  () => _statusFilter = value!.isEmpty ? null : value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<Opportunity>>(
            future: widget.deps.repository.loadAll(),
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <Opportunity>[];
              final filtered = all.where((o) {
                final matchesStatus =
                    _statusFilter == null || o.status == _statusFilter;
                if (!matchesStatus) return false;
                if (_query.isEmpty) return true;
                final haystack = [
                  o.displayTitle,
                  o.analysis.role ?? '',
                  o.analysis.company ?? '',
                  o.text ?? '',
                ].join(' ').toLowerCase();
                return haystack.contains(_query.toLowerCase());
              }).toList();
              if (filtered.isEmpty) {
                return SurfaceCard(
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 30,
                            color: colors.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            all.isEmpty
                                ? 'Nothing captured yet. Analyze a post to fill your inbox.'
                                : 'No opportunities match this search or filter.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final opportunity in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SurfaceCard(
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              opportunity.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_statusLabel(opportunity.status)} · ${_formatDate(opportunity.createdAt)}'
                              '${opportunity.capturedVia == 'radar' ? ' · radar' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () => _openDetail(opportunity),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail(Opportunity opportunity) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OpportunityDetail(
        deps: widget.deps,
        opportunity: opportunity,
        outreach: OutreachService(widget.deps),
        onChanged: () => setState(() {}),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'new' => 'New',
  'need-action' => 'Need action',
  'applied' => 'Applied',
  'follow-up' => 'Follow-up',
  'archived' => 'Archived',
  _ => status,
};

String _formatDate(DateTime utc) {
  final local = utc.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Detail sheet: analysis, connection tracking, and ready-made outreach.
/// The user performs every send; drafts are copied or handed to their apps.
class _OpportunityDetail extends StatefulWidget {
  const _OpportunityDetail({
    required this.deps,
    required this.opportunity,
    required this.outreach,
    required this.onChanged,
  });

  final AppDependencies deps;
  final Opportunity opportunity;
  final OutreachService outreach;
  final VoidCallback onChanged;

  @override
  State<_OpportunityDetail> createState() => _OpportunityDetailState();
}

class _OpportunityDetailState extends State<_OpportunityDetail> {
  String? _busyKind;
  String? _error;

  Opportunity get _opportunity => widget.opportunity;

  Future<void> _generate(String kind) async {
    setState(() {
      _busyKind = kind;
      _error = null;
    });
    try {
      await widget.outreach.generate(opportunity: _opportunity, kind: kind);
    } on AiAnalysisException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busyKind = null);
      widget.onChanged();
    }
  }

  Future<void> _markRequested() async {
    await widget.outreach.markRequested(_opportunity);
    widget.onChanged();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminders every ${widget.deps.settings.reminderHours} h until you mark it accepted.',
          ),
        ),
      );
    }
  }

  Future<void> _markAccepted() async {
    await widget.outreach.markAccepted(_opportunity);
    widget.onChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied. Paste it and send it yourself.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final analysis = _opportunity.analysis;
    final scenario = _opportunity.scenario;
    final note = _opportunity.drafts['connectionNote'];
    final dm = _opportunity.drafts['dm'];
    final email = _opportunity.drafts['email'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _opportunity.displayTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Captured ${_formatDate(_opportunity.createdAt)} · ${_statusLabel(_opportunity.status)}'
              '${_opportunity.capturedVia == 'radar' ? ' · by radar' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (analysis.summary != null) ...[
              SelectableText(analysis.summary!),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (scenario.wantsDm)
                  const Chip(
                    avatar: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    label: Text('DM ask'),
                  ),
                if (scenario.wantsEmail) ...[
                  const SizedBox(width: 8),
                  const Chip(
                    avatar: Icon(Icons.alternate_email_rounded, size: 16),
                    label: Text('Email ask'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Outreach — prepared for you, sent by you',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Notice(
              icon: Icons.shield_outlined,
              text: 'Nothing is ever sent automatically. You copy the material or open your own apps and press send.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ---- DM path -----------------------------------------------
            if (scenario.wantsDm) ...[
              const SectionLabel('Direct message path'),
              const SizedBox(height: 10),
              switch (_opportunity.connectionState) {
                'none' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you connected with the poster?',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busyKind == null
                              ? () => _generate('connectionNote')
                              : null,
                          icon: _busyKind == 'connectionNote'
                              ? const _MiniSpinner()
                              : const Icon(
                                  Icons.person_add_alt_1_outlined,
                                  size: 18,
                                ),
                          label: const Text(
                            'Not connected — craft connection note',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busyKind == null
                              ? () => _generate('dm')
                              : null,
                          icon: _busyKind == 'dm'
                              ? const _MiniSpinner()
                              : const Icon(Icons.chat_outlined, size: 18),
                          label: const Text(
                            'Already connected — write my message',
                          ),
                        ),
                      ],
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 16),
                      _DraftCard(
                        title: 'Connection note',
                        body: note.body,
                        maxHint: 200,
                        onCopy: () => _copy('Connection note', note.body),
                        onRegenerate: _busyKind == null
                            ? () => _generate('connectionNote')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _busyKind == null ? _markRequested : null,
                        icon: const Icon(
                          Icons.schedule_send_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'I sent the request — remind me to check',
                        ),
                      ),
                    ],
                  ],
                ),
                'requested' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Notice(
                      icon: Icons.hourglass_top_rounded,
                      text:
                          'Request sent. You will get reminders every '
                          '${widget.deps.settings.reminderHours} h. When they accept, tap below '
                          'and copy your personalized message.',
                    ),
                    const SizedBox(height: 12),
                    if (dm != null)
                      _DraftCard(
                        title: 'Personalized message (ready to copy)',
                        body: dm.body,
                        maxHint: 500,
                        onCopy: () => _copy('Message', dm.body),
                        onRegenerate: _busyKind == null
                            ? () => _generate('dm')
                            : null,
                      )
                    else
                      FilledButton.icon(
                        onPressed: _busyKind == null
                            ? () => _generate('dm')
                            : null,
                        icon: _busyKind == 'dm'
                            ? const _MiniSpinner()
                            : const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('They accepted — write my message'),
                      ),
                    if (dm != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busyKind == null ? _markAccepted : null,
                        child: const Text('They accepted — stop reminders'),
                      ),
                    ],
                  ],
                ),
                'accepted' =>
                  dm == null
                      ? FilledButton.icon(
                          onPressed: _busyKind == null
                              ? () => _generate('dm')
                              : null,
                          icon: _busyKind == 'dm'
                              ? const _MiniSpinner()
                              : const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('Write my personalized message'),
                        )
                      : _DraftCard(
                          title: 'Personalized message',
                          body: dm.body,
                          maxHint: 500,
                          onCopy: () => _copy('Message', dm.body),
                          onRegenerate: _busyKind == null
                              ? () => _generate('dm')
                              : null,
                        ),
                _ => const SizedBox.shrink(),
              },
              const SizedBox(height: 20),
            ],

            // ---- Email path --------------------------------------------
            if (scenario.wantsEmail) ...[
              const SectionLabel('Email path'),
              const SizedBox(height: 10),
              if (email == null)
                FilledButton.icon(
                  onPressed: _busyKind == null
                      ? () => _generate('email')
                      : null,
                  icon: _busyKind == 'email'
                      ? const _MiniSpinner()
                      : const Icon(Icons.alternate_email_rounded, size: 18),
                  label: const Text('Craft the email'),
                )
              else ...[
                _DraftCard(
                  title: 'Email draft',
                  subject: email.subject,
                  body: email.body,
                  onCopySubject: email.subject == null
                      ? null
                      : () => _copy('Subject', email.subject!),
                  onCopy: () => _copy('Email body', email.body),
                  onRegenerate: _busyKind == null
                      ? () => _generate('email')
                      : null,
                  trailing: FilledButton.tonalIcon(
                    onPressed: _busyKind == null
                        ? () => _openEmailApp(email)
                        : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open in email app'),
                  ),
                ),
                if (widget.outreach.resume.storedPath == null) ...[
                  const SizedBox(height: 8),
                  const Notice(
                    text: 'No resume stored yet. Add one in Settings and it will be attached when you open the email app.',
                  ),
                ],
              ],
              const SizedBox(height: 20),
            ],

            const Divider(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in Opportunity.statuses)
                  if (status != _opportunity.status)
                    OutlinedButton(
                      onPressed: () async {
                        await widget.deps.repository.save(
                          _opportunity.copyWith(status: status),
                        );
                        widget.onChanged();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text(_statusLabel(status)),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                await widget.deps.repository.delete(_opportunity.id);
                if (context.mounted) Navigator.of(context).pop();
                widget.onChanged();
              },
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: colors.error,
              ),
              label: Text(
                'Delete from this device',
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEmailApp(OutreachDraft email) async {
    await AndroidBridge.openEmail(
      to: _extractEmail(_opportunity),
      subject: email.subject ?? 'Application — ${_opportunity.displayTitle}',
      body: email.body,
      attachmentPath: widget.outreach.resume.storedPath,
    );
  }

  String _extractEmail(Opportunity opportunity) {
    final haystack =
        '${opportunity.analysis.applyInstructions ?? ''} ${opportunity.text ?? ''}';
    final match = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+').firstMatch(haystack);
    return match?.group(0) ?? '';
  }
}

class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.title,
    required this.body,
    required this.onCopy,
    required this.onRegenerate,
    this.subject,
    this.maxHint,
    this.onCopySubject,
    this.trailing,
  });

  final String title;
  final String? subject;
  final String body;
  final int? maxHint;
  final Future<void> Function() onCopy;
  final Future<void> Function()? onCopySubject;
  final VoidCallback? onRegenerate;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final overLimit = maxHint != null && body.length > maxHint!;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (maxHint != null)
                Text(
                  '${body.length}/$maxHint',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overLimit ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (subject != null) ...[
            const SizedBox(height: 8),
            Text(
              'Subject',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            SelectableText(subject!),
          ],
          const SizedBox(height: 8),
          SelectableText(body),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
              if (onCopySubject != null)
                OutlinedButton(
                  onPressed: onCopySubject,
                  child: const Text('Copy subject'),
                ),
              if (onRegenerate != null)
                TextButton(
                  onPressed: onRegenerate,
                  child: const Text('Regenerate'),
                ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

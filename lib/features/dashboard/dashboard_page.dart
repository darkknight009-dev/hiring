import 'package:flutter/material.dart';

import '../../app_dependencies.dart';
import '../../models/opportunity_entity.dart';
import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.deps,
    required this.onAnalyze,
    required this.onOpenOpportunities,
  });

  final AppDependencies deps;
  final VoidCallback onAnalyze;
  final VoidCallback onOpenOpportunities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListenableBuilder(
      listenable: deps,
      builder: (context, _) => PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('A little clarity for your next big move'),
            const SizedBox(height: 14),
            Text(
              'Your opportunity inbox.',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Less “I’ll come back to this.” More following through.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            _WelcomeCard(onAnalyze: onAnalyze),
            const SizedBox(height: 32),
            _MetricCards(deps: deps),
            const SizedBox(height: 32),
            Text('Recent Opportunities', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'A home for the posts worth coming back to.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Opportunity>>(
              future: deps.repository.loadAll(),
              builder: (context, snapshot) {
                final opportunities = snapshot.data ?? const <Opportunity>[];
                final recent = opportunities.take(3).toList();
                if (recent.isEmpty) {
                  return SurfaceCard(
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.07),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.inbox_outlined,
                              color: colors.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'A fresh start. A clear radar.',
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(
                              'No opportunities yet. Capture a LinkedIn post you’d like to follow up on.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: onAnalyze,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Capture your first post'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final opportunity in recent)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SurfaceCard(
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                opportunity.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                opportunity.status,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 20,
                              ),
                              onTap: onOpenOpportunities,
                            ),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onOpenOpportunities,
                        icon: const Icon(Icons.inbox_outlined, size: 18),
                        label: const Text('Open your inbox'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Notice(
              icon: Icons.lock_outline_rounded,
              text: 'Foundation preview · Your inbox is stored on this device only. Analysis uses your own AI key; nothing is sent on your behalf.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCards extends StatelessWidget {
  const _MetricCards({required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<List<Opportunity>>(
      future: deps.repository.loadAll(),
      builder: (context, snapshot) {
        final opportunities = snapshot.data ?? const <Opportunity>[];
        final needAction = opportunities
            .where((o) => o.status == 'need-action' || o.status == 'follow-up')
            .length;
        final applied = opportunities
            .where((o) => o.status == 'applied')
            .length;
        final metrics = [
          (Icons.radar_rounded, 'Opportunities', opportunities.length),
          (Icons.bolt_outlined, 'Need action', needAction),
          (Icons.check_circle_outline, 'Applied', applied),
          (
            Icons.schedule_outlined,
            'Follow-ups',
            opportunities.where((o) => o.status == 'follow-up').length,
          ),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            metric.$1,
                            size: 19,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '${metric.$3}',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metric.$2,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onAnalyze});

  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.radar_rounded, color: colors.primary, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Never miss a hiring post.',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Turn a post in your feed into your next opportunity. Capture the details, prepare your outreach, and make your move—on your terms.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text(
              'Analyze LinkedIn Post',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Manual capture. No feed scraping. You’re always in control.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

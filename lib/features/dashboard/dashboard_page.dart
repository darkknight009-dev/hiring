import 'package:flutter/material.dart';

import '../../widgets/page_content.dart';
import '../../widgets/surface_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onAnalyze});

  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('A little clarity for your next big move'),
          const SizedBox(height: 14),
          Text('Your opportunity inbox.', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 12),
          Text(
            'Less “I’ll come back to this.” More following through.',
            style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          _WelcomeCard(onAnalyze: onAnalyze),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 4 : 2;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in const [
                    (Icons.radar_rounded, 'Opportunities'),
                    (Icons.bolt_outlined, 'Need action'),
                    (Icons.check_circle_outline, 'Applied'),
                    (Icons.schedule_outlined, 'Follow-ups'),
                  ])
                    SizedBox(
                      width: width,
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(metric.$1, size: 19, color: colors.onSurfaceVariant),
                            const SizedBox(height: 14),
                            Text('0', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(metric.$2, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Text('Recent Opportunities', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('A home for the posts worth coming back to.', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          SurfaceCard(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.07), shape: BoxShape.circle),
                    child: Icon(Icons.inbox_outlined, color: colors.primary, size: 28),
                  ),
                  const SizedBox(height: 18),
                  Text('A fresh start. A clear radar.', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      'No opportunities yet. Start by capturing a LinkedIn post you’d like to follow up on.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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
          ),
          const SizedBox(height: 24),
          const Notice(
            icon: Icons.lock_outline_rounded,
            text: 'Foundation preview · Your inbox is empty. Capture previews stay in this tab; analysis and saved opportunities are coming next.',
          ),
        ],
      ),
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
              Expanded(child: Text('Never miss a hiring post.', style: theme.textTheme.headlineSmall)),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Turn a post in your feed into your next opportunity. Capture the details, prepare your outreach, and make your move—on your terms.',
              style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Analyze LinkedIn Post', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 14),
          Text('Manual capture. No feed scraping. You’re always in control.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

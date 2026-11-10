import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../quote_models.dart';
import '../quote_repository.dart';
import 'quote_preview_screen.dart';

class QuotesScreen extends ConsumerWidget {
  const QuotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(quotationsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SmartQuotes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/quotes/new'),
        backgroundColor: AppColors.brandDeep,
        foregroundColor: AppColors.onBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New quotation'),
      ),
      body: quotes.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(quotationsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.request_quote_outlined,
              title: 'No quotations yet',
              message:
                  'Describe a project and let Gemini draft line items and milestones for you to refine.',
              actionLabel: 'Create a quotation',
              onAction: () => context.push('/quotes/new'),
            );
          }
          final open = list.where(
            (q) =>
                q.status == QuoteStatus.sent ||
                q.status == QuoteStatus.accepted,
          );
          final openValue = open.fold<int>(
            0,
            (s, q) => s + q.totals.totalMinor - q.paidMinor,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xs,
              Space.gutter,
              96,
            ),
            children: [
              AppCard(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AWAITING PAYMENT',
                      style: t.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(Money.format(openValue), style: t.headlineMedium),
                    Text(
                      '${open.length} sent or accepted quotations',
                      style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              for (final q in list) ...[
                AppCard(
                  onTap: () => context.push('/quotes/${q.id}'),
                  child: Row(
                    children: [
                      const IconTile(Icons.description_outlined),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.projectTitle,
                              style: t.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${q.clientName} · ${q.number}',
                              style: t.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Money.format(
                              q.totals.totalMinor,
                              currency: q.currency,
                            ),
                            style: t.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          StatusBadge(
                            q.status.label,
                            tone: quoteTone(q.status),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../split_repository.dart';

class SplitListScreen extends ConsumerWidget {
  const SplitListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(expenseGroupsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SmartSplit')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/split/new'),
        backgroundColor: AppColors.brandDeep,
        foregroundColor: AppColors.onBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New split'),
      ),
      body: groups.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(expenseGroupsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.call_split_rounded,
              title: 'No shared expenses yet',
              message:
                  'Split a bill equally or by custom amounts, then track who has paid you back.',
              actionLabel: 'Split a bill',
              onAction: () => context.push('/split/new'),
            );
          }
          final outstanding = list.fold<int>(
            0,
            (s, g) => s + g.outstandingMinor,
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
                      'OUTSTANDING TO YOU',
                      style: t.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: Space.xxs),
                    Text(Money.format(outstanding), style: t.headlineMedium),
                    const SizedBox(height: Space.xxs),
                    Text(
                      'Across ${list.where((g) => !g.isSettled).length} open splits · tracked by you',
                      style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              for (final g in list) ...[
                AppCard(
                  onTap: () => context.push('/split/${g.id}'),
                  child: Row(
                    children: [
                      const IconTile(Icons.receipt_outlined),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.title, style: t.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${g.participants.length} people · ${g.debtors.where((p) => p.settled).length}/${g.debtors.length} settled',
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
                            Money.format(g.totalMinor, currency: g.currency),
                            style: t.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          StatusBadge(
                            g.isSettled ? 'Settled' : 'Open',
                            tone: g.isSettled ? Tone.positive : Tone.warning,
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

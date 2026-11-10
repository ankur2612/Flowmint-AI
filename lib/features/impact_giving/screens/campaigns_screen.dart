import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/payments/payment_models.dart';
import '../../../core/payments/payment_status_screen.dart';
import '../../../core/payments/paypal_service.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../campaign_repository.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key, this.cause});

  /// Optional cause from the assistant used to highlight matching campaigns.
  final String? cause;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(campaignsProvider);
    final donations = ref.watch(paymentRecordsProvider(PaymentKind.donation));
    final t = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ImpactGiving'),
          bottom: const TabBar(
            indicatorColor: AppColors.brand,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textTertiary,
            dividerColor: AppColors.border,
            tabs: [
              Tab(text: 'Campaigns'),
              Tab(text: 'My donations'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            campaigns.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorState(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(campaignsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'No campaigns yet',
                    message:
                        'Donation campaigns appear here once they have been reviewed and published by FLOWMINT.',
                  );
                }
                final c = cause?.trim();
                final sorted = [...list];
                if (c != null && c.isNotEmpty) {
                  sorted.sort(
                    (a, b) =>
                        (b.matchesCause(c) ? 1 : 0) -
                        (a.matchesCause(c) ? 1 : 0),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(Space.gutter),
                  children: [
                    if (c != null && c.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Text(
                          'Campaigns related to "$c" are shown first.',
                          style: t.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    for (final campaign in sorted) ...[
                      CampaignCard(campaign: campaign),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                );
              },
            ),
            donations.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorState(message: friendlyError(e)),
              data: (list) => list.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: 'No donations yet',
                      message:
                          'Donations you make through FLOWMINT are listed here once PayPal confirms them.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(Space.gutter),
                      children: [
                        for (final d in list) ...[
                          AppCard(
                            onTap: () =>
                                context.push('/payments/donation/${d.id}'),
                            child: Row(
                              children: [
                                const IconTile(Icons.favorite_rounded),
                                const SizedBox(width: Space.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.campaignTitle ?? d.description,
                                        style: t.titleSmall,
                                      ),
                                      if (d.createdAt != null)
                                        Text(
                                          DateFormat(
                                            'd MMM yyyy',
                                          ).format(d.createdAt!),
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
                                        d.amountMinor,
                                        currency: d.currency,
                                      ),
                                      style: t.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    StatusBadge(
                                      d.status.label,
                                      tone: paymentTone(d.status),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CampaignCard extends StatelessWidget {
  const CampaignCard({super.key, required this.campaign, this.amountMinor});

  final Campaign campaign;
  final int? amountMinor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = campaign;
    final goal = c.goalMinor;
    return AppCard(
      onTap: () => context.push(
        '/giving/${c.id}${amountMinor == null ? '' : '?amount=$amountMinor'}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (c.category.isNotEmpty)
                StatusBadge(c.category, tone: Tone.info),
              const Spacer(),
              if (c.organizationVerified)
                const Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: AppColors.brand,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Verified organisation',
                      style: TextStyle(fontSize: 11.5, color: AppColors.brand),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(c.title, style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            c.organization,
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (c.isDemo) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                const StatusBadge('DEMO CAMPAIGN', tone: Tone.info),
                const SizedBox(width: Space.xs),
                if (goal != null)
                  Flexible(
                    child: Text(
                      'Illustrative target ${Money.format(goal, currency: c.currency)}',
                      style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ] else if (goal != null && goal > 0) ...[
            const SizedBox(height: Space.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: (c.raisedMinor / goal).clamp(0, 1),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${Money.format(c.raisedMinor, currency: c.currency)} raised via FLOWMINT of ${Money.format(goal, currency: c.currency)}',
              style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

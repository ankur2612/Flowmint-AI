import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/payments/payment_models.dart';
import '../../../core/payments/paypal_service.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../refund_models.dart';
import '../refund_repository.dart';

Tone refundTone(RefundStatus s) => switch (s) {
  RefundStatus.refunded => Tone.positive,
  RefundStatus.rejected => Tone.danger,
  RefundStatus.draft => Tone.neutral,
  _ => Tone.warning,
};

class RefundsScreen extends ConsumerWidget {
  const RefundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(refundRequestsProvider);
    final orders = ref.watch(paymentRecordsProvider(PaymentKind.shopping));
    final t = Theme.of(context).textTheme;
    final eligibleOrders = (orders.valueOrNull ?? const <PaymentRecord>[])
        .where(
          (o) => o.status == PaymentStatus.completed && o.refundStatus == null,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Refund Assistant')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/refunds/new'),
        backgroundColor: AppColors.brandDeep,
        foregroundColor: AppColors.onBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New request'),
      ),
      body: requests.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(refundRequestsProvider),
        ),
        data: (list) {
          if (list.isEmpty && eligibleOrders.isEmpty) {
            return EmptyState(
              icon: Icons.undo_rounded,
              title: 'No refund requests',
              message:
                  'Scan a receipt and Gemini will help you check the refund policy and draft a request to the merchant.',
              actionLabel: 'Start a request',
              onAction: () => context.push('/refunds/new'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xs,
              Space.gutter,
              96,
            ),
            children: [
              if (eligibleOrders.isNotEmpty) ...[
                const SectionHeader('FLOWMINT orders paid with PayPal'),
                for (final o in eligibleOrders) ...[
                  AppCard(
                    onTap: () => context.push('/refunds/new', extra: o.id),
                    child: Row(
                      children: [
                        const IconTile(Icons.shopping_bag_outlined),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            o.description,
                            style: t.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Money.format(o.amountMinor, currency: o.currency),
                          style: t.titleSmall,
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                const SizedBox(height: Space.lg),
              ],
              if (list.isNotEmpty) const SectionHeader('Your requests'),
              for (final r in list) ...[
                AppCard(
                  onTap: () => context.push('/refunds/${r.id}'),
                  child: Row(
                    children: [
                      const IconTile(Icons.receipt_long_outlined),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.merchant, style: t.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              r.reason,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                          if (r.amountMinor != null)
                            Text(
                              Money.format(
                                r.amountMinor!,
                                currency: r.currency,
                              ),
                              style: t.titleSmall,
                            ),
                          const SizedBox(height: 4),
                          StatusBadge(
                            r.status.label,
                            tone: refundTone(r.status),
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

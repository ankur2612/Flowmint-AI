import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/app_card.dart';
import '../widgets/surfaces.dart';
import '../widgets/state_views.dart';
import 'payment_models.dart';
import 'paypal_service.dart';

Tone paymentTone(PaymentStatus s) => switch (s) {
  PaymentStatus.completed => Tone.positive,
  PaymentStatus.pending || PaymentStatus.created => Tone.warning,
  PaymentStatus.failed => Tone.danger,
  PaymentStatus.refunded || PaymentStatus.partiallyRefunded => Tone.info,
  PaymentStatus.cancelled => Tone.neutral,
};

/// Live view of a server-verified payment record (shopping order or donation).
class PaymentStatusScreen extends ConsumerWidget {
  const PaymentStatusScreen({super.key, required this.kind, required this.id});

  final PaymentKind kind;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(paymentRecordProvider((kind, id)));
    return Scaffold(
      appBar: AppBar(
        title: Text(kind == PaymentKind.shopping ? 'Order' : 'Donation'),
      ),
      body: record.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(paymentRecordProvider((kind, id))),
        ),
        data: (r) => r == null
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Record not found',
                message: 'This payment record does not exist or was removed.',
              )
            : _RecordView(record: r),
      ),
    );
  }
}

class _RecordView extends StatelessWidget {
  const _RecordView({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = record;
    final tone = paymentTone(r.status);
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');
    final icon = switch (r.status) {
      PaymentStatus.completed => Icons.check_rounded,
      PaymentStatus.failed => Icons.close_rounded,
      PaymentStatus.cancelled => Icons.block_rounded,
      PaymentStatus.refunded ||
      PaymentStatus.partiallyRefunded => Icons.undo_rounded,
      _ => Icons.schedule_rounded,
    };
    final explanation = switch (r.status) {
      PaymentStatus.completed =>
        'PayPal confirmed this payment to the FLOWMINT backend.',
      PaymentStatus.pending =>
        'PayPal is still processing this payment. This page updates automatically.',
      PaymentStatus.created =>
        'This order was created but not approved in PayPal. You have not been charged.',
      PaymentStatus.failed =>
        r.failureReason ??
            'PayPal declined this payment. You have not been charged.',
      PaymentStatus.cancelled =>
        'Checkout was cancelled. You have not been charged.',
      PaymentStatus.refunded => 'PayPal confirmed the refund of this payment.',
      PaymentStatus.partiallyRefunded =>
        'Part of this payment was refunded through PayPal.',
    };

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.md),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Container(
              key: ValueKey(r.status),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.color.withValues(alpha: 0.14),
              ),
              child: Icon(icon, color: tone.color, size: 34),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Center(
          child: Text(
            Money.format(r.amountMinor, currency: r.currency),
            style: t.displaySmall,
          ),
        ),
        const SizedBox(height: Space.xs),
        Center(child: StatusBadge(r.status.label, tone: tone)),
        const SizedBox(height: Space.sm),
        Text(
          explanation,
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: Space.xl),
        LightPanel(
          child: Column(
            children: [
              DetailRow('Description', r.description),
              if (r.recipient != null) DetailRow('Paid to', r.recipient!),
              if (r.campaignTitle != null)
                DetailRow('Campaign', r.campaignTitle!),
              const DetailRow('Payment method', 'PayPal'),
              if (r.createdAt != null)
                DetailRow('Created', dateFmt.format(r.createdAt!)),
              if (r.completedAt != null)
                DetailRow('Completed', dateFmt.format(r.completedAt!)),
              if (r.paypalOrderId != null)
                DetailRow('PayPal order', r.paypalOrderId!),
              if (r.captureId != null) DetailRow('Capture ID', r.captureId!),
              if (r.refundedMinor > 0)
                DetailRow(
                  'Refunded',
                  Money.format(r.refundedMinor, currency: r.currency),
                ),
            ],
          ),
        ),
        if (r.items.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const SectionHeader('Items'),
          LightPanel(
            child: Column(
              children: [
                for (final i in r.items)
                  DetailRow(
                    '${i.quantity} × ${i.name}',
                    Money.format(
                      i.unitPriceMinor * i.quantity,
                      currency: r.currency,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (r.kind == PaymentKind.shopping &&
            r.status == PaymentStatus.completed &&
            r.refundStatus == null) ...[
          const SizedBox(height: Space.xl),
          OutlinedButton.icon(
            onPressed: () => context.push('/refunds/new', extra: r.id),
            icon: const Icon(Icons.undo_rounded, size: 19),
            label: const Text('Request a refund'),
          ),
        ],
        if (r.refundStatus != null) ...[
          const SizedBox(height: Space.md),
          Center(
            child: StatusBadge(
              'Refund ${r.refundStatus!.toLowerCase()}',
              tone: Tone.info,
            ),
          ),
        ],
      ],
    );
  }
}

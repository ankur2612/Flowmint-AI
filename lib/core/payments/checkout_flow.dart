import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/app_card.dart';
import '../widgets/surfaces.dart';
import '../widgets/state_views.dart';
import 'payment_models.dart';
import 'paypal_checkout_screen.dart';
import 'paypal_service.dart';

class CheckoutResult {
  const CheckoutResult(this.recordId, this.kind, this.status);
  final String recordId;
  final PaymentKind kind;
  final PaymentStatus status;
}

/// Orchestrates every PayPal payment in FLOWMINT:
///
/// 1. the user reviews and explicitly confirms the action,
/// 2. the backend creates the PayPal order (prices computed server-side),
/// 3. the buyer approves inside PayPal,
/// 4. the backend captures and verifies the payment.
///
/// A payment is only reported as completed when step 4 says so.
abstract final class CheckoutFlow {
  static final _inFlight = <String>{};

  static Future<CheckoutResult?> run(
    BuildContext context,
    WidgetRef ref, {
    required PaymentReview review,
    required CheckoutRequest request,
  }) async {
    final key = request.idempotencyKey;
    if (_inFlight.contains(key)) return null;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentReviewSheet(review: review),
    );
    if (confirmed != true || !context.mounted) return null;

    _inFlight.add(key);
    final service = ref.read(paypalServiceProvider);
    final navigator = Navigator.of(context);
    try {
      final session = await _withProgress(
        context,
        'Preparing secure PayPal checkout…',
        () => service.createOrder(request),
      );
      if (session.status.isFinal) {
        // The idempotency key matched an order that is already settled.
        return CheckoutResult(session.recordId, session.kind, session.status);
      }
      if (session.amountMinor != review.amountMinor ||
          session.currency != review.currency) {
        await service.cancel(session);
        throw const PaymentException(
          'The price changed since you reviewed this order. Please review it again.',
        );
      }

      final outcome = await navigator.push<CheckoutOutcome>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PayPalCheckoutScreen(session: session),
        ),
      );
      if (!context.mounted) return null;

      if (outcome != CheckoutOutcome.approved) {
        await service.cancel(session);
        return CheckoutResult(
          session.recordId,
          session.kind,
          PaymentStatus.cancelled,
        );
      }

      final status = await _withProgress(
        context,
        'Confirming payment with PayPal…',
        () => service.capture(session),
      );
      return CheckoutResult(session.recordId, session.kind, status);
    } on PaymentException catch (e) {
      if (context.mounted) showMessage(context, e.message);
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<T> _withProgress<T>(
    BuildContext context,
    String label,
    Future<T> Function() task,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: LoadingView(label: label),
          ),
        ),
      ),
    );
    try {
      return await task();
    } finally {
      navigator.pop();
    }
  }
}

class _PaymentReviewSheet extends StatelessWidget {
  const _PaymentReviewSheet({required this.review});

  final PaymentReview review;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REVIEW PAYMENT',
              style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: Space.xs),
            Text(review.title, style: t.headlineSmall),
            const SizedBox(height: Space.xxs),
            Text(
              review.description,
              style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: Space.lg),
            Center(
              child: Text(
                Money.format(review.amountMinor, currency: review.currency),
                style: t.displaySmall,
              ),
            ),
            const SizedBox(height: Space.lg),
            LightPanel(
              child: Column(
                children: [
                  DetailRow('Pay to', review.recipient),
                  const DetailRow('Payment method', 'PayPal'),
                  for (final (label, value) in review.details)
                    DetailRow(label, value),
                  const Divider(height: Space.lg),
                  DetailRow(
                    'Total',
                    Money.format(review.amountMinor, currency: review.currency),
                    emphasize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: AppColors.brand,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    'You will approve this payment inside PayPal. FLOWMINT '
                    'never sees your PayPal password or card details, and '
                    'nothing is charged until you approve.',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.lock_outline_rounded, size: 19),
              label: const Text('Confirm and continue to PayPal'),
            ),
            const SizedBox(height: Space.xs),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

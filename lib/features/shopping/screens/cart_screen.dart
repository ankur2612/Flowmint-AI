import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/payments/checkout_flow.dart';
import '../../../core/payments/payment_models.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../cart_controller.dart';
import '../widgets/product_widgets.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _checkout(
    BuildContext context,
    WidgetRef ref,
    CartState cart,
  ) async {
    final currency = cart.currency!;
    final result = await CheckoutFlow.run(
      context,
      ref,
      review: PaymentReview(
        title: 'Shopping order',
        description:
            '${cart.count} item${cart.count == 1 ? '' : 's'} from ${AppConstants.merchantName}',
        amountMinor: cart.totalMinor,
        currency: currency,
        recipient: AppConstants.merchantName,
        details: [
          for (final i in cart.items)
            (
              '${i.quantity} × ${i.product.name}',
              Money.format(i.lineMinor, currency: currency),
            ),
          if (AppConstants.isSandbox)
            ('Environment', 'PayPal Sandbox · test funds'),
        ],
      ),
      request: ShoppingCheckoutRequest(cart.checkoutKey, [
        for (final i in cart.items)
          PaymentLineItem(productId: i.product.id, quantity: i.quantity),
      ]),
    );
    if (result == null || !context.mounted) return;
    if (result.status == PaymentStatus.cancelled) {
      showMessage(context, 'Checkout cancelled. You have not been charged.');
      return;
    }
    if (result.status == PaymentStatus.completed ||
        result.status == PaymentStatus.pending) {
      ref.read(cartProvider.notifier).clear();
    }
    context.pushReplacement('/payments/${result.kind.wire}/${result.recordId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final t = Theme.of(context).textTheme;
    final controller = ref.read(cartProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Review order')),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message:
                  'Ask the assistant to find something, or browse the catalogue.',
              actionLabel: 'Browse products',
              onAction: () => context.pushReplacement('/shop'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.xs,
                Space.gutter,
                Space.xxl,
              ),
              children: [
                for (final i in cart.items) ...[
                  AppCard(
                    padding: const EdgeInsets.all(Space.sm),
                    child: Row(
                      children: [
                        ProductImage(i.product.imageUrl, size: 56),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.product.name,
                                style: t.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                Money.format(
                                  i.product.priceMinor,
                                  currency: i.product.currency,
                                ),
                                style: t.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Stepper(
                          quantity: i.quantity,
                          onChanged: (q) =>
                              controller.setQuantity(i.product.id, q),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                ],
                const SizedBox(height: Space.md),
                AppCard(
                  child: Column(
                    children: [
                      DetailRow('Items', '${cart.count}'),
                      DetailRow('Sold by', AppConstants.merchantName),
                      const DetailRow('Payment method', 'PayPal'),
                      const Divider(height: Space.lg),
                      DetailRow(
                        'Total',
                        Money.format(cart.totalMinor, currency: cart.currency!),
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'Prices are confirmed by the FLOWMINT backend from the live catalogue when you check out.',
                  style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.md,
                ),
                child: cart.items.any((i) => i.product.isDemo)
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Your cart contains demo products, which are for demonstration only and cannot be purchased.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: Space.xs),
                          const FilledButton(
                            onPressed: null,
                            child: Text('Checkout unavailable for demo items'),
                          ),
                        ],
                      )
                    : FilledButton.icon(
                        onPressed: () => _checkout(context, ref, cart),
                        icon: const Icon(Icons.lock_outline_rounded, size: 19),
                        label: Text(
                          'Checkout · ${Money.format(cart.totalMinor, currency: cart.currency!)}',
                        ),
                      ),
              ),
            ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: quantity == 1 ? 'Remove' : 'Decrease',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              quantity == 1
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
              size: 18,
            ),
            onPressed: () => onChanged(quantity - 1),
          ),
          Text('$quantity', style: Theme.of(context).textTheme.titleSmall),
          IconButton(
            tooltip: 'Increase',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 18),
            onPressed: quantity >= CartController.maxQuantity
                ? null
                : () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

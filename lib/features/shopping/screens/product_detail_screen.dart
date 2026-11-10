import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../cart_controller.dart';
import '../catalog_repository.dart';
import '../shopping_models.dart';
import '../widgets/product_widgets.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.id});

  final String id;

  void _add(
    BuildContext context,
    WidgetRef ref,
    Product p, {
    bool goToCart = false,
  }) {
    final error = ref.read(cartProvider.notifier).add(p);
    if (error != null) {
      showMessage(context, error);
    } else if (goToCart) {
      context.push('/cart');
    } else {
      showMessage(context, 'Added to cart');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(id));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(actions: const [CartButton()]),
      body: product.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(productProvider(id)),
        ),
        data: (p) => p == null
            ? const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Product unavailable',
                message: 'This product is no longer in the catalogue.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.xxl,
                ),
                children: [
                  Center(child: ProductImage(p.imageUrl, size: 220)),
                  const SizedBox(height: Space.lg),
                  if (p.isDemo)
                    const Padding(
                      padding: EdgeInsets.only(bottom: Space.sm),
                      child: StatusBadge(
                        'DEMO PRODUCT · NOT FOR SALE',
                        tone: Tone.info,
                      ),
                    ),
                  Text(
                    p.brand.toUpperCase(),
                    style: t.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(p.name, style: t.headlineSmall),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Text(
                        Money.format(p.priceMinor, currency: p.currency),
                        style: t.headlineMedium?.copyWith(
                          color: AppColors.brand,
                        ),
                      ),
                      const Spacer(),
                      StatusBadge(
                        p.inStock ? 'In stock' : 'Out of stock',
                        tone: p.inStock ? Tone.positive : Tone.danger,
                      ),
                    ],
                  ),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Text(
                      p.description,
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (p.specs.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    const SectionHeader('Specifications'),
                    AppCard(
                      child: Column(
                        children: [
                          for (final e in p.specs.entries)
                            DetailRow(e.key, e.value),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
      bottomNavigationBar: product.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: product.value!.inStock
                            ? () => _add(context, ref, product.value!)
                            : null,
                        child: const Text('Add to cart'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: product.value!.inStock
                            ? () => _add(
                                context,
                                ref,
                                product.value!,
                                goToCart: true,
                              )
                            : null,
                        child: const Text('Buy now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

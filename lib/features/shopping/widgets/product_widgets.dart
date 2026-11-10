import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/surfaces.dart';
import '../cart_controller.dart';
import '../shopping_models.dart';

class ProductImage extends StatelessWidget {
  const ProductImage(this.url, {super.key, this.size = 64});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.inventory_2_outlined,
        color: AppColors.textTertiary,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }
}

/// Product row used for search results, recommendations and assistant cards.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    this.reason,
    this.selected,
    this.onSelectChanged,
  });

  final Product product;
  final String? reason;
  final bool? selected;
  final ValueChanged<bool>? onSelectChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    return LightPanel(
      onTap: () => context.push('/shop/product/${p.id}'),
      padding: const EdgeInsets.all(Space.sm),
      borderColor: selected == true
          ? AppColors.brandDeep
          : AppColors.paperBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(p.imageUrl),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: t.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ),
                    if (p.isDemo) ...[
                      const SizedBox(width: Space.xs),
                      const StatusBadge('DEMO', tone: Tone.info),
                    ],
                  ],
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  Money.format(p.priceMinor, currency: p.currency),
                  style: t.titleSmall?.copyWith(color: AppColors.brandDeep),
                ),
                if (reason != null && reason!.isNotEmpty) ...[
                  const SizedBox(height: Space.xxs + 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 13,
                          color: AppColors.brandDeep,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          reason!,
                          style: t.bodySmall?.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onSelectChanged != null)
            Checkbox(
              value: selected ?? false,
              onChanged: (v) => onSelectChanged!(v ?? false),
            ),
        ],
      ),
    );
  }
}

class CartButton extends ConsumerWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider.select((c) => c.count));
    return IconButton(
      tooltip: 'Cart',
      onPressed: () => context.push('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: AppColors.brandDeep,
        textColor: AppColors.onBrand,
        label: Text('$count'),
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

/// Side-by-side comparison of selected products' catalogue specs.
void showComparison(BuildContext context, List<Product> products) {
  final keys = <String>{for (final p in products) ...p.specs.keys}.toList();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final t = Theme.of(context).textTheme;
      Widget cell(String text, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.xs,
        ),
        child: Text(text, style: style ?? t.bodySmall),
      );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            0,
            Space.gutter,
            Space.xl,
          ),
          children: [
            Text('Compare', style: t.titleLarge),
            const SizedBox(height: Space.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(140),
                columnWidths: const {0: FixedColumnWidth(110)},
                border: const TableBorder(
                  horizontalInside: BorderSide(color: AppColors.border),
                ),
                children: [
                  TableRow(
                    children: [
                      cell(''),
                      for (final p in products)
                        cell(p.name, style: t.titleSmall),
                    ],
                  ),
                  TableRow(
                    children: [
                      cell(
                        'Price',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      for (final p in products)
                        cell(
                          Money.format(p.priceMinor, currency: p.currency),
                          style: t.titleSmall?.copyWith(color: AppColors.brand),
                        ),
                    ],
                  ),
                  TableRow(
                    children: [
                      cell(
                        'Brand',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      for (final p in products) cell(p.brand),
                    ],
                  ),
                  for (final k in keys)
                    TableRow(
                      children: [
                        cell(
                          k,
                          style: t.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        for (final p in products) cell(p.specs[k] ?? '—'),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

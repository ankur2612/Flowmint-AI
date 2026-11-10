import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../catalog_repository.dart';
import '../shopping_agent.dart';
import '../shopping_models.dart';
import '../widgets/product_widgets.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final _query = TextEditingController();
  final _selected = <String>{};
  ShoppingResult? _result;
  String? _error;
  bool _searching = false;
  String? _category;

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      _query.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _selected.clear();
    });
    try {
      final r = await ref.read(shoppingAgentProvider).recommend(q);
      if (mounted) setState(() => _result = r);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggle(Product p, bool on) => setState(() {
    if (!on) {
      _selected.remove(p.id);
    } else if (_selected.length < 3) {
      _selected.add(p.id);
    } else {
      showMessage(context, 'Compare up to three products at a time.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final catalog = ref.watch(catalogProvider);
    final products = catalog.valueOrNull ?? const <Product>[];
    final categories = {
      for (final p in products) p.category,
    }.where((c) => c.isNotEmpty).toList()..sort();
    final browse = _category == null
        ? products
        : products.where((p) => p.category == _category).toList();
    final selectedProducts = products
        .where((p) => _selected.contains(p.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping Agent'),
        actions: const [CartButton()],
      ),
      floatingActionButton: selectedProducts.length >= 2
          ? FloatingActionButton.extended(
              onPressed: () => showComparison(context, selectedProducts),
              backgroundColor: AppColors.brandDeep,
              foregroundColor: AppColors.onBrand,
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text('Compare ${selectedProducts.length}'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xs,
          Space.gutter,
          96,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'A laptop under ₹60,000 for programming',
              prefixIcon: const Icon(
                Icons.auto_awesome,
                color: AppColors.brand,
                size: 20,
              ),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _search,
                    ),
            ),
          ),
          const SizedBox(height: Space.lg),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildResults(t),
          ),
          catalog.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.xxl),
              child: LoadingView(),
            ),
            error: (e, _) => ErrorState(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(catalogProvider),
            ),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'The catalogue is empty',
                    message:
                        'No products have been published to this FLOWMINT store yet. '
                        'Products appear here once the merchant adds them to the catalogue.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('Browse catalogue'),
                      if (list.any((p) => p.isDemo))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: Row(
                            children: [
                              const StatusBadge(
                                'DEMO CATALOGUE',
                                tone: Tone.info,
                              ),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                child: Text(
                                  'Sample products with illustrative prices.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: _category == null,
                              onSelected: (_) =>
                                  setState(() => _category = null),
                            ),
                            for (final c in categories)
                              Padding(
                                padding: const EdgeInsets.only(left: Space.xs),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: _category == c,
                                  onSelected: (_) =>
                                      setState(() => _category = c),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      for (final p in browse) ...[
                        ProductTile(
                          product: p,
                          selected: _selected.contains(p.id),
                          onSelectChanged: (v) => _toggle(p, v),
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(TextTheme t) {
    if (_error != null) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: AppCard(
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _search, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final r = _result;
    if (r == null || r.catalogueEmpty) {
      return const SizedBox.shrink(key: ValueKey('none'));
    }
    return Column(
      key: ValueKey(r),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Recommended for you'),
        if (r.summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              r.summary!,
              style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        if (r.recommendations.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.search_off_rounded,
            title: 'No matching products',
            message:
                'Nothing in the catalogue fits this request. Try a different budget or description.',
          ),
        for (final rec in r.recommendations) ...[
          ProductTile(
            product: rec.product,
            reason: rec.reason,
            selected: _selected.contains(rec.product.id),
            onSelectChanged: (v) => _toggle(rec.product, v),
          ),
          const SizedBox(height: Space.sm),
        ],
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

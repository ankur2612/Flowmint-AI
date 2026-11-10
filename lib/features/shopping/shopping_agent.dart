import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import '../../core/utils/json_read.dart';
import '../../core/utils/money.dart';
import 'catalog_repository.dart';
import 'shopping_models.dart';

/// Conversational product discovery over the real catalogue. Gemini only
/// ranks products it is given; any id it returns that is not in the
/// catalogue is discarded, and budgets are enforced in code.
class ShoppingAgent {
  ShoppingAgent(this._catalog, this._gemini);
  final CatalogRepository _catalog;
  final GeminiService _gemini;

  static const _maxCandidates = 80;

  static final _schema = Schema.object(
    properties: {
      'budgetMax': Schema.number(
        nullable: true,
        description:
            'Maximum budget stated by the user, in major units, or null.',
      ),
      'summary': Schema.string(
        description: 'One sentence explaining how the picks were chosen.',
      ),
      'picks': Schema.array(
        maxItems: 4,
        items: Schema.object(
          properties: {
            'productId': Schema.string(),
            'reason': Schema.string(
              description:
                  'Why it fits the request, citing real specs. Max 25 words.',
            ),
          },
        ),
      ),
    },
    optionalProperties: ['budgetMax'],
  );

  /// [budgetCurrency] applies to [maxBudgetMinor] and to any budget the user
  /// states in [query]; products priced in another currency are excluded when
  /// a budget applies, since amounts in different currencies are not comparable.
  Future<ShoppingResult> recommend(
    String query, {
    int? maxBudgetMinor,
    String budgetCurrency = AppConstants.defaultCurrency,
  }) async {
    final products = (await _catalog.fetchActive())
        .where((p) => p.inStock)
        .toList();
    if (products.isEmpty) {
      return const ShoppingResult(recommendations: [], catalogueEmpty: true);
    }
    bool withinBudget(Product p, int budget) =>
        p.currency == budgetCurrency && p.priceMinor <= budget;
    var candidates = maxBudgetMinor == null
        ? products
        : products.where((p) => withinBudget(p, maxBudgetMinor)).toList();
    if (candidates.isEmpty) {
      return ShoppingResult(
        recommendations: const [],
        catalogueEmpty: false,
        budgetMinor: maxBudgetMinor,
        summary: 'No products in the catalogue fit within this budget.',
      );
    }
    if (candidates.length > _maxCandidates) {
      candidates = candidates.sublist(0, _maxCandidates);
    }

    final json = await _gemini.generateJson(
      instruction:
          'You are a shopping assistant for the FLOWMINT catalogue. Choose up '
          'to 3 products that best match the request, using ONLY ids from the '
          'provided catalogue. Never invent products, specs or prices. Respect '
          'any budget the user states. If nothing fits, return no picks.',
      prompt:
          'Request: $query\n\nCatalogue JSON:\n'
          '${jsonEncode(candidates.map((p) => p.toAiJson()).toList())}',
      schema: _schema,
      temperature: 0.1,
    );

    final statedBudget = Money.fromMajor(Read.number(json['budgetMax']));
    final budget = maxBudgetMinor ?? statedBudget;
    final byId = {for (final p in candidates) p.id: p};
    final seen = <String>{};
    final recs = <Recommendation>[];
    for (final pick in Read.maps(json['picks'])) {
      final product = byId[Read.str(pick['productId'])];
      if (product == null || !seen.add(product.id)) continue;
      if (budget != null && !withinBudget(product, budget)) continue;
      recs.add(Recommendation(product, Read.str(pick['reason'])));
      if (recs.length == 3) break;
    }
    return ShoppingResult(
      recommendations: recs,
      catalogueEmpty: false,
      budgetMinor: budget,
      summary: Read.strOrNull(json['summary']),
    );
  }
}

final shoppingAgentProvider = Provider<ShoppingAgent>(
  (ref) => ShoppingAgent(
    ref.watch(catalogRepositoryProvider),
    ref.watch(geminiServiceProvider),
  ),
);

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import '../../core/utils/json_read.dart';
import '../../core/utils/money.dart';
import 'quote_models.dart';

/// Drafts an initial quotation from a natural-language project description.
/// The result is always a draft the freelancer edits and approves.
class QuoteAi {
  QuoteAi(this._gemini);
  final GeminiService _gemini;

  static final _schema = Schema.object(
    properties: {
      'projectTitle': Schema.string(),
      'projectDescription': Schema.string(
        description: 'Two or three sentences describing the scope.',
      ),
      'clientName': Schema.string(nullable: true),
      'lineItems': Schema.array(
        minItems: 1,
        maxItems: 12,
        items: Schema.object(
          properties: {
            'description': Schema.string(),
            'quantity': Schema.number(),
            'unitPrice': Schema.number(
              description: 'Price per unit in major currency units.',
            ),
          },
        ),
      ),
      'milestones': Schema.array(
        maxItems: 5,
        items: Schema.object(
          properties: {
            'title': Schema.string(),
            'percent': Schema.integer(minimum: 1, maximum: 100),
          },
        ),
        description: 'Payment milestones whose percentages sum to 100.',
      ),
      'notes': Schema.string(
        nullable: true,
        description: 'Assumptions and exclusions, short.',
      ),
    },
    optionalProperties: ['clientName', 'notes'],
  );

  Future<QuoteSeed> draft(String description, {String? clientName}) async {
    final json = await _gemini.generateJson(
      instruction:
          'You help freelancers draft professional quotations. Break the work '
          'into clear deliverable line items. Prices are in '
          '${AppConstants.defaultCurrency}. If the user states a budget, keep '
          'the total within it. Otherwise propose reasonable estimates; they '
          'will be shown as AI suggestions for the freelancer to adjust. Do not '
          'include taxes in line items.',
      prompt: [
        'Project: $description',
        if (clientName != null) 'Client: $clientName',
      ].join('\n'),
      schema: _schema,
      temperature: 0.4,
    );

    final items = <QuoteLineItem>[];
    for (final m in Read.maps(json['lineItems'])) {
      final desc = Read.strOrNull(m['description']);
      final qty = Read.number(m['quantity']) ?? 1;
      final price = Money.fromMajor(Read.number(m['unitPrice']));
      if (desc == null || price == null || qty <= 0 || qty > 10000) continue;
      items.add(
        QuoteLineItem(description: desc, quantity: qty, unitPriceMinor: price),
      );
    }
    if (items.isEmpty) {
      throw const AiException(
        'Could not draft line items for this project. Add more detail and try again.',
      );
    }

    var milestones = [
      for (final m in Read.maps(json['milestones']))
        if (Read.strOrNull(m['title']) != null &&
            Read.integer(m['percent']) > 0)
          QuoteMilestone(
            title: Read.str(m['title']),
            percent: Read.integer(m['percent']),
          ),
    ];
    if (milestones.fold<int>(0, (s, m) => s + m.percent) != 100) {
      milestones = const [
        QuoteMilestone(title: 'Advance', percent: 50),
        QuoteMilestone(title: 'On delivery', percent: 50),
      ];
    }

    return QuoteSeed(
      projectTitle: Read.strOrNull(json['projectTitle']),
      projectDescription:
          Read.strOrNull(json['projectDescription']) ?? description,
      clientName: clientName ?? Read.strOrNull(json['clientName']),
      items: items,
      milestones: milestones,
      notes: Read.strOrNull(json['notes']),
      aiSuggested: true,
    );
  }
}

final quoteAiProvider = Provider<QuoteAi>(
  (ref) => QuoteAi(ref.watch(geminiServiceProvider)),
);

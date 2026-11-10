import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import 'assistant_models.dart';

/// Intent routing: Gemini classifies the request and prepares a structured
/// action. It can never execute anything — the app validates the result and
/// the user approves any financial step.
class AssistantAi {
  AssistantAi(this._gemini);
  final GeminiService _gemini;

  static const _historyTurns = 10;

  static final _schema = Schema.object(
    properties: {
      'intent': Schema.enumString(
        enumValues: [for (final i in AssistantIntent.values) i.wire],
      ),
      'reply': Schema.string(
        description:
            'User-facing response, at most 90 words, friendly and precise. '
            'Simple Markdown is allowed (bold, bullet lists, short tables).',
      ),
      'actionType': Schema.enumString(
        enumValues: [for (final a in AssistantAction.values) a.wire],
      ),
      'requiresConfirmation': Schema.boolean(),
      'missingInformation': Schema.array(
        items: Schema.string(),
        description:
            'Details still needed from the user to complete the action.',
      ),
      'suggestedWorkflow': Schema.array(
        items: Schema.string(),
        description:
            'Up to 4 short next steps the app will take, e.g. "Review shares".',
      ),
      'parameters': Schema.object(
        properties: {
          'amount': Schema.number(nullable: true, description: 'Major units.'),
          'currency': Schema.string(nullable: true, description: 'ISO 4217.'),
          'participantCount': Schema.integer(nullable: true),
          'participants': Schema.array(items: Schema.string()),
          'title': Schema.string(nullable: true),
          'merchant': Schema.string(nullable: true),
          'orderReference': Schema.string(nullable: true),
          'reason': Schema.string(nullable: true),
          'cause': Schema.string(
            nullable: true,
            description: 'Donation cause keyword, e.g. education.',
          ),
          'productQuery': Schema.string(nullable: true),
          'maxBudget': Schema.number(
            nullable: true,
            description: 'Major units.',
          ),
          'clientName': Schema.string(nullable: true),
          'projectDescription': Schema.string(nullable: true),
        },
        optionalProperties: [
          'amount',
          'currency',
          'participantCount',
          'participants',
          'title',
          'merchant',
          'orderReference',
          'reason',
          'cause',
          'productQuery',
          'maxBudget',
          'clientName',
          'projectDescription',
        ],
      ),
    },
  );

  String _instruction() =>
      '''
You are FLOWMINT AI, the assistant inside a personal finance app. Today is ${DateFormat('yyyy-MM-dd').format(DateTime.now())}. Default currency: ${AppConstants.defaultCurrency}.

Classify every request into exactly one intent and choose the matching action:
- SMART_SPLIT → PREPARE_SPLIT: splitting a bill or group expense. Extract amount, participantCount (include the user), participant names, and a short title. If a bill (photo or PDF) is attached, read the total from it.
- AI_SHOPPING → SEARCH_PRODUCTS: finding or buying products. Put the full need in productQuery and any budget in maxBudget.
- SMART_QUOTES → DRAFT_QUOTATION: preparing a quotation, estimate or proposal for a client. Put the scope in projectDescription and the client in clientName.
- SUBSCRIPTION_INTELLIGENCE → REVIEW_SUBSCRIPTIONS: questions about recurring subscriptions or their cost.
- REFUND_ASSISTANCE → PREPARE_REFUND_REQUEST: refunds, returns, faulty purchases. Extract merchant, orderReference, amount and reason (from an attached receipt photo or PDF if present).
- IMPACT_GIVING → PREPARE_DONATION: donating or charity. Extract amount and cause.
- GENERAL_FINANCIAL_QUERY → NONE: anything else that is financial, or when the request is ambiguous. Ask a clarifying question when ambiguous.

Rules:
- You cannot move money. Never say a payment, transfer, donation or refund has happened or will be approved. You only prepare actions the user reviews and approves.
- Never invent products, prices, charities, statistics or account data. Product and campaign results come from the app's catalogue afterwards.
- requiresConfirmation is true for any action that may lead to a payment.
- List required details that are missing in missingInformation and ask for them briefly in reply; still choose the action when the intent is clear.
- If the request is not about money, reply politely that you help with financial tasks; intent GENERAL_FINANCIAL_QUERY, action NONE.
- For general questions give short educational information, not personalised investment, tax or legal advice.''';

  Future<AssistantResponse> interpret({
    required List<ChatMessage> history,
    required String text,
    AiDocument? image,
  }) async {
    final turns = history
        .where((m) => !m.isError && m.text.trim().isNotEmpty)
        .toList()
        .reversed
        .take(_historyTurns)
        .toList()
        .reversed;
    // Merge consecutive turns of the same role (e.g. after a failed reply)
    // and start with a user turn, as the Gemini API expects.
    final merged = <(ChatRole, String)>[];
    for (final m in turns) {
      if (merged.isNotEmpty && merged.last.$1 == m.role) {
        merged[merged.length - 1] = (m.role, '${merged.last.$2}\n${m.text}');
      } else {
        merged.add((m.role, m.text));
      }
    }
    while (merged.isNotEmpty && merged.first.$1 == ChatRole.assistant) {
      merged.removeAt(0);
    }
    // The new request is the final user turn; fold an unanswered earlier
    // user turn into it rather than sending two user turns in a row.
    var prompt = text.trim().isEmpty
        ? 'Here is a document. What can you help me with?'
        : text;
    if (merged.isNotEmpty && merged.last.$1 == ChatRole.user) {
      prompt = '${merged.removeLast().$2}\n$prompt';
    }
    final contents = <Content>[
      for (final (role, t) in merged)
        role == ChatRole.user ? Content.text(t) : Content.model([TextPart(t)]),
    ];

    final json = await _gemini.generateJson(
      instruction: _instruction(),
      prompt: prompt,
      schema: _schema,
      history: contents,
      document: image,
    );
    return AssistantResponse.fromModel(json);
  }
}

final assistantAiProvider = Provider<AssistantAi>(
  (ref) => AssistantAi(ref.watch(geminiServiceProvider)),
);

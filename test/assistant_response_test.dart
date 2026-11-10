import 'package:flowmint_ai/features/assistant/assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssistantResponse.fromModel', () {
    test('routes a split request with validated parameters', () {
      final r = AssistantResponse.fromModel({
        'intent': 'SMART_SPLIT',
        'reply': 'Here is the split.',
        'actionType': 'PREPARE_SPLIT',
        'requiresConfirmation': false,
        'parameters': {
          'amount': 2400,
          'participantCount': 4,
          'title': 'Dinner',
        },
      });
      expect(r.intent, AssistantIntent.smartSplit);
      expect(r.action, AssistantAction.prepareSplit);
      expect(r.parameters.amountMinor, 240000);
      expect(r.parameters.participantCount, 4);
    });

    test('drops an action that does not belong to the detected intent', () {
      final r = AssistantResponse.fromModel({
        'intent': 'GENERAL_FINANCIAL_QUERY',
        'reply': 'Sure.',
        'actionType': 'PREPARE_DONATION',
        'requiresConfirmation': false,
      });
      expect(r.action, AssistantAction.none);
    });

    test('forces confirmation for actions that can lead to payment', () {
      final r = AssistantResponse.fromModel({
        'intent': 'IMPACT_GIVING',
        'reply': 'Let us find a campaign.',
        'actionType': 'PREPARE_DONATION',
        'requiresConfirmation': false,
        'parameters': {'amount': 500, 'cause': 'education'},
      });
      expect(r.requiresConfirmation, isTrue);
      expect(r.parameters.amountMinor, 50000);
    });

    test('discards invalid amounts and participant counts', () {
      final r = AssistantResponse.fromModel({
        'intent': 'SMART_SPLIT',
        'reply': 'How much was it?',
        'actionType': 'PREPARE_SPLIT',
        'requiresConfirmation': false,
        'parameters': {
          'amount': -10,
          'participantCount': 1,
          'currency': 'rupees',
        },
      });
      expect(r.parameters.amountMinor, isNull);
      expect(r.parameters.participantCount, isNull);
      expect(r.parameters.currency, 'INR');
    });

    test('falls back safely on unknown or missing fields', () {
      final r = AssistantResponse.fromModel({'intent': 'TRANSFER_MONEY'});
      expect(r.intent, AssistantIntent.generalFinancialQuery);
      expect(r.action, AssistantAction.none);
      expect(r.reply, isNotEmpty);
    });

    test('survives a serialisation round trip', () {
      final original = AssistantResponse.fromModel({
        'intent': 'AI_SHOPPING',
        'reply': 'Searching the catalogue.',
        'actionType': 'SEARCH_PRODUCTS',
        'parameters': {
          'productQuery': 'laptop for programming',
          'maxBudget': 60000,
        },
      });
      final restored = AssistantResponse.fromModel(original.toJson());
      expect(restored.action, AssistantAction.searchProducts);
      expect(restored.parameters.maxBudgetMinor, 6000000);
      expect(restored.requiresConfirmation, isTrue);
    });
  });
}

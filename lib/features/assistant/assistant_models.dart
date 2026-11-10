import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/json_read.dart';
import '../../core/utils/money.dart';
import '../smart_quotes/quote_models.dart';

enum AssistantIntent {
  smartSplit('SMART_SPLIT', 'SmartSplit'),
  refundAssistance('REFUND_ASSISTANCE', 'Refund Assistant'),
  impactGiving('IMPACT_GIVING', 'ImpactGiving'),
  smartQuotes('SMART_QUOTES', 'SmartQuotes'),
  subscriptionIntelligence('SUBSCRIPTION_INTELLIGENCE', 'Subscriptions'),
  aiShopping('AI_SHOPPING', 'Shopping Agent'),
  generalFinancialQuery('GENERAL_FINANCIAL_QUERY', 'General');

  const AssistantIntent(this.wire, this.label);
  final String wire;
  final String label;

  static AssistantIntent fromWire(String? v) => values.firstWhere(
    (i) => i.wire == v,
    orElse: () => generalFinancialQuery,
  );
}

enum AssistantAction {
  none('NONE', null),
  prepareSplit('PREPARE_SPLIT', AssistantIntent.smartSplit),
  prepareRefundRequest(
    'PREPARE_REFUND_REQUEST',
    AssistantIntent.refundAssistance,
  ),
  prepareDonation('PREPARE_DONATION', AssistantIntent.impactGiving),
  draftQuotation('DRAFT_QUOTATION', AssistantIntent.smartQuotes),
  reviewSubscriptions(
    'REVIEW_SUBSCRIPTIONS',
    AssistantIntent.subscriptionIntelligence,
  ),
  searchProducts('SEARCH_PRODUCTS', AssistantIntent.aiShopping);

  const AssistantAction(this.wire, this.intent);
  final String wire;

  /// The only intent this action is valid for.
  final AssistantIntent? intent;

  /// Actions that can lead to a PayPal payment always require explicit
  /// confirmation, regardless of what the model returned.
  bool get mayLeadToPayment =>
      this == prepareDonation || this == searchProducts;

  static AssistantAction fromWire(String? v) =>
      values.firstWhere((a) => a.wire == v, orElse: () => none);
}

/// Parameters the model extracted from the request. All optional; workflows
/// validate what they need.
class ActionParameters {
  const ActionParameters({
    this.amountMinor,
    this.currency = AppConstants.defaultCurrency,
    this.participantCount,
    this.participants = const [],
    this.title,
    this.merchant,
    this.orderReference,
    this.reason,
    this.cause,
    this.productQuery,
    this.maxBudgetMinor,
    this.clientName,
    this.projectDescription,
  });

  final int? amountMinor;
  final String currency;
  final int? participantCount;
  final List<String> participants;
  final String? title;
  final String? merchant;
  final String? orderReference;
  final String? reason;
  final String? cause;
  final String? productQuery;
  final int? maxBudgetMinor;
  final String? clientName;
  final String? projectDescription;

  factory ActionParameters.fromJson(Map<String, dynamic> j) {
    final currency = Read.strOrNull(j['currency'])?.toUpperCase();
    final count = j['participantCount'] == null
        ? null
        : Read.integer(j['participantCount']);
    return ActionParameters(
      amountMinor: Money.fromMajor(Read.number(j['amount'])),
      currency: currency != null && RegExp(r'^[A-Z]{3}$').hasMatch(currency)
          ? currency
          : AppConstants.defaultCurrency,
      participantCount: count != null && count >= 2 && count <= 50
          ? count
          : null,
      participants: Read.strings(j['participants']).take(50).toList(),
      title: Read.strOrNull(j['title']),
      merchant: Read.strOrNull(j['merchant']),
      orderReference: Read.strOrNull(j['orderReference']),
      reason: Read.strOrNull(j['reason']),
      cause: Read.strOrNull(j['cause']),
      productQuery: Read.strOrNull(j['productQuery']),
      maxBudgetMinor: Money.fromMajor(Read.number(j['maxBudget'])),
      clientName: Read.strOrNull(j['clientName']),
      projectDescription: Read.strOrNull(j['projectDescription']),
    );
  }

  Map<String, dynamic> toJson() => {
    'amount': amountMinor == null ? null : amountMinor! / 100,
    'currency': currency,
    'participantCount': participantCount,
    'participants': participants,
    'title': title,
    'merchant': merchant,
    'orderReference': orderReference,
    'reason': reason,
    'cause': cause,
    'productQuery': productQuery,
    'maxBudget': maxBudgetMinor == null ? null : maxBudgetMinor! / 100,
    'clientName': clientName,
    'projectDescription': projectDescription,
  };
}

/// Structured result of intent routing.
class AssistantResponse {
  const AssistantResponse({
    required this.intent,
    required this.reply,
    required this.action,
    required this.requiresConfirmation,
    this.missingInformation = const [],
    this.suggestedWorkflow = const [],
    this.parameters = const ActionParameters(),
  });

  final AssistantIntent intent;
  final String reply;
  final AssistantAction action;
  final bool requiresConfirmation;
  final List<String> missingInformation;
  final List<String> suggestedWorkflow;
  final ActionParameters parameters;

  /// Parses model output and enforces application rules: an action must
  /// belong to the detected intent, and payment-capable actions always
  /// require confirmation. Invalid values were already dropped by
  /// [ActionParameters.fromJson].
  factory AssistantResponse.fromModel(Map<String, dynamic> j) {
    final intent = AssistantIntent.fromWire(Read.strOrNull(j['intent']));
    var action = AssistantAction.fromWire(Read.strOrNull(j['actionType']));
    if (action.intent != null && action.intent != intent) {
      action = AssistantAction.none;
    }
    final reply =
        Read.strOrNull(j['reply']) ??
        "I'm not sure how to help with that yet. Could you rephrase it?";
    return AssistantResponse(
      intent: intent,
      reply: reply,
      action: action,
      requiresConfirmation:
          action.mayLeadToPayment || Read.boolean(j['requiresConfirmation']),
      missingInformation: Read.strings(
        j['missingInformation'],
      ).take(6).toList(),
      suggestedWorkflow: Read.strings(j['suggestedWorkflow']).take(6).toList(),
      parameters: ActionParameters.fromJson(Read.map(j['parameters'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'intent': intent.wire,
    'reply': reply,
    'actionType': action.wire,
    'requiresConfirmation': requiresConfirmation,
    'missingInformation': missingInformation,
    'suggestedWorkflow': suggestedWorkflow,
    'parameters': parameters.toJson(),
  };
}

/// Data the app attached to an assistant message after running the
/// workflow the model selected (catalogue search, quote drafting, …).
sealed class ActionAttachment {
  const ActionAttachment();

  Map<String, dynamic> toJson();

  static ActionAttachment? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return switch (Read.str(j['kind'])) {
      'products' => ProductPicksAttachment.fromJson(j),
      'quote' => QuoteDraftAttachment(QuoteSeed.fromJson(Read.map(j['seed']))),
      'subscriptions' => SubscriptionSnapshotAttachment.fromJson(j),
      'campaigns' => CampaignMatchesAttachment.fromJson(j),
      _ => null,
    };
  }
}

class ProductPick {
  const ProductPick(
    this.productId,
    this.name,
    this.priceMinor,
    this.currency,
    this.reason,
    this.imageUrl,
  );
  final String productId;
  final String name;
  final int priceMinor;
  final String currency;
  final String reason;
  final String? imageUrl;
}

class ProductPicksAttachment extends ActionAttachment {
  const ProductPicksAttachment({
    required this.query,
    required this.picks,
    required this.catalogueEmpty,
    this.summary,
  });

  final String query;
  final List<ProductPick> picks;
  final bool catalogueEmpty;
  final String? summary;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'products',
    'query': query,
    'catalogueEmpty': catalogueEmpty,
    'summary': summary,
    'picks': [
      for (final p in picks)
        {
          'productId': p.productId,
          'name': p.name,
          'priceMinor': p.priceMinor,
          'currency': p.currency,
          'reason': p.reason,
          'imageUrl': p.imageUrl,
        },
    ],
  };

  factory ProductPicksAttachment.fromJson(Map<String, dynamic> j) =>
      ProductPicksAttachment(
        query: Read.str(j['query']),
        catalogueEmpty: Read.boolean(j['catalogueEmpty']),
        summary: Read.strOrNull(j['summary']),
        picks: [
          for (final p in Read.maps(j['picks']))
            ProductPick(
              Read.str(p['productId']),
              Read.str(p['name']),
              Read.integer(p['priceMinor']),
              Read.str(p['currency']),
              Read.str(p['reason']),
              Read.strOrNull(p['imageUrl']),
            ),
        ],
      );
}

class QuoteDraftAttachment extends ActionAttachment {
  const QuoteDraftAttachment(this.seed);
  final QuoteSeed seed;

  @override
  Map<String, dynamic> toJson() => {'kind': 'quote', 'seed': seed.toJson()};
}

class SubscriptionSnapshotAttachment extends ActionAttachment {
  const SubscriptionSnapshotAttachment({
    required this.monthlyMinor,
    required this.annualMinor,
    required this.activeCount,
    required this.currency,
    this.topCategory,
    this.nextRenewalName,
    this.nextRenewalDate,
  });

  final int monthlyMinor;
  final int annualMinor;
  final int activeCount;
  final String currency;
  final String? topCategory;
  final String? nextRenewalName;
  final DateTime? nextRenewalDate;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'subscriptions',
    'monthlyMinor': monthlyMinor,
    'annualMinor': annualMinor,
    'activeCount': activeCount,
    'currency': currency,
    'topCategory': topCategory,
    'nextRenewalName': nextRenewalName,
    'nextRenewalDate': nextRenewalDate?.toIso8601String(),
  };

  factory SubscriptionSnapshotAttachment.fromJson(Map<String, dynamic> j) =>
      SubscriptionSnapshotAttachment(
        monthlyMinor: Read.integer(j['monthlyMinor']),
        annualMinor: Read.integer(j['annualMinor']),
        activeCount: Read.integer(j['activeCount']),
        currency: Read.str(j['currency'], AppConstants.defaultCurrency),
        topCategory: Read.strOrNull(j['topCategory']),
        nextRenewalName: Read.strOrNull(j['nextRenewalName']),
        nextRenewalDate: Read.date(j['nextRenewalDate']),
      );
}

class CampaignMatch {
  const CampaignMatch(this.id, this.title, this.organization);
  final String id;
  final String title;
  final String organization;
}

class CampaignMatchesAttachment extends ActionAttachment {
  const CampaignMatchesAttachment(this.matches);
  final List<CampaignMatch> matches;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'campaigns',
    'matches': [
      for (final m in matches)
        {'id': m.id, 'title': m.title, 'organization': m.organization},
    ],
  };

  factory CampaignMatchesAttachment.fromJson(Map<String, dynamic> j) =>
      CampaignMatchesAttachment([
        for (final m in Read.maps(j['matches']))
          CampaignMatch(
            Read.str(m['id']),
            Read.str(m['title']),
            Read.str(m['organization']),
          ),
      ]);
}

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.hasImage = false,
    this.response,
    this.attachment,
    this.actionCompletedRoute,
    this.retryForMessageId,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final bool hasImage;
  final AssistantResponse? response;
  final ActionAttachment? attachment;

  /// Set once the user completed the prepared action (e.g. saved the split),
  /// so the same message cannot create a duplicate record.
  final String? actionCompletedRoute;

  /// Non-null for a local, unsaved error bubble: the id of the user message
  /// whose request failed and can be retried.
  final String? retryForMessageId;

  bool get isError => retryForMessageId != null;

  ChatMessage withCompletedRoute(String route) => ChatMessage(
    id: id,
    role: role,
    text: text,
    createdAt: createdAt,
    hasImage: hasImage,
    response: response,
    attachment: attachment,
    actionCompletedRoute: route,
  );

  Map<String, dynamic> toMap() => {
    'role': role.name,
    'text': text,
    'createdAt': Timestamp.fromDate(createdAt),
    'hasImage': hasImage,
    'response': response?.toJson(),
    'attachment': attachment?.toJson(),
    'actionCompletedRoute': actionCompletedRoute,
  };

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      role: Read.str(m['role']) == 'user' ? ChatRole.user : ChatRole.assistant,
      text: Read.str(m['text']),
      createdAt: Read.date(m['createdAt']) ?? DateTime.now(),
      hasImage: Read.boolean(m['hasImage']),
      response: m['response'] is Map
          ? AssistantResponse.fromModel(Read.map(m['response']))
          : null,
      attachment: ActionAttachment.fromJson(
        m['attachment'] is Map ? Read.map(m['attachment']) : null,
      ),
      actionCompletedRoute: Read.strOrNull(m['actionCompletedRoute']),
    );
  }
}

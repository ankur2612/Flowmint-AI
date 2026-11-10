import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/services/gemini_service.dart';
import '../../core/utils/money.dart';
import '../activity/activity_repository.dart';
import 'refund_models.dart';

class RefundRepository extends UserScopedRepository {
  const RefundRepository(super.userDoc, this._activity, this._gemini);
  final ActivityRepository _activity;
  final GeminiService _gemini;

  Stream<List<RefundRequest>> watchAll() => !isSignedIn
      ? const Stream.empty()
      : collection('refund_requests')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((q) => q.docs.map(RefundRequest.fromDoc).toList());

  Future<RefundRequest?> fetch(String id) async {
    final s = await collection('refund_requests').doc(id).get();
    return s.exists ? RefundRequest.fromDoc(s) : null;
  }

  Future<String> save(RefundRequest r) async {
    final ref = r.id.isEmpty
        ? collection('refund_requests').doc()
        : collection('refund_requests').doc(r.id);
    await ref.set(r.toMap());
    // PayPal refunds of FLOWMINT orders are recorded in activity by the
    // backend; only user-managed requests are tracked from the client.
    if (r.linkedOrderId == null) {
      await _activity.record(
        type: ActivityType.refund,
        refId: ref.id,
        status: switch (r.status) {
          RefundStatus.refunded => ActivityStatus.completed,
          RefundStatus.rejected => ActivityStatus.cancelled,
          _ => ActivityStatus.pending,
        },
        title: 'Refund request · ${r.merchant}',
        subtitle: r.status.label,
        route: '/refunds/${ref.id}',
        createdAt: r.createdAt,
        amountMinor: r.amountMinor,
        currency: r.currency,
      );
    }
    return ref.id;
  }

  Future<void> delete(String id) async {
    await collection('refund_requests').doc(id).delete();
    await _activity.remove(ActivityType.refund, id);
  }

  static final _analysisSchema = Schema.object(
    properties: {
      'eligibility': Schema.enumString(
        enumValues: ['likely', 'unclear', 'unlikely'],
      ),
      'summary': Schema.string(
        description:
            'Two sentences on eligibility, citing the policy when given.',
      ),
      'requiredInformation': Schema.array(items: Schema.string(), maxItems: 8),
      'missingInformation': Schema.array(items: Schema.string(), maxItems: 8),
      'draftMessage': Schema.string(
        description: 'A polite, concise refund request to the merchant.',
      ),
    },
  );

  /// Gemini reviews the request against any policy text the user provided
  /// and drafts a message. It never claims the merchant will approve it.
  Future<RefundAnalysis> analyse(RefundRequest r) async {
    final json = await _gemini.generateJson(
      instruction:
          'You help consumers prepare refund requests. Assess eligibility only '
          'from the policy text provided; if there is no policy text, say the '
          'merchant policy is unknown and use "unclear". Never state or imply '
          'that the merchant has approved or will approve the refund. Keep the '
          "draft message factual and under 160 words, signed as 'Customer'.",
      prompt: [
        'Merchant: ${r.merchant}',
        if (r.orderReference != null) 'Order reference: ${r.orderReference}',
        if (r.purchaseDate != null)
          'Purchase date: ${DateFormat('yyyy-MM-dd').format(r.purchaseDate!)}',
        'Today: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
        if (r.amountMinor != null)
          'Amount: ${Money.formatWithCode(r.amountMinor!, r.currency)}',
        'Reason: ${r.reason}',
        'Refund policy text: ${r.policyText ?? '(not provided)'}',
      ].join('\n'),
      schema: _analysisSchema,
    );
    return RefundAnalysis.fromMap(json);
  }
}

final refundRepositoryProvider = Provider<RefundRepository>(
  (ref) => RefundRepository(
    ref.watch(userDocProvider),
    ref.watch(activityRepositoryProvider),
    ref.watch(geminiServiceProvider),
  ),
);

final refundRequestsProvider = StreamProvider.autoDispose<List<RefundRequest>>(
  (ref) => ref.watch(refundRepositoryProvider).watchAll(),
);

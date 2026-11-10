import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import '../../core/utils/json_read.dart';

/// Progress of a refund request. For external merchants the user reports the
/// status; for FLOWMINT orders refunded through PayPal it reflects the
/// backend-verified refund on the order record.
enum RefundStatus {
  draft('Draft'),
  submitted('Sent to merchant'),
  processing('Processing'),
  refunded('Refunded'),
  rejected('Declined');

  const RefundStatus(this.label);
  final String label;

  static RefundStatus fromWire(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => draft);
}

enum Eligibility {
  likely('Likely eligible'),
  unclear('Needs more information'),
  unlikely('Likely not eligible');

  const Eligibility(this.label);
  final String label;

  static Eligibility fromWire(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => unclear);
}

class RefundAnalysis {
  const RefundAnalysis({
    required this.eligibility,
    required this.summary,
    required this.requiredInformation,
    required this.missingInformation,
    required this.draftMessage,
  });

  final Eligibility eligibility;
  final String summary;
  final List<String> requiredInformation;
  final List<String> missingInformation;
  final String draftMessage;

  Map<String, dynamic> toMap() => {
    'eligibility': eligibility.name,
    'summary': summary,
    'requiredInformation': requiredInformation,
    'missingInformation': missingInformation,
    'draftMessage': draftMessage,
  };

  factory RefundAnalysis.fromMap(Map<String, dynamic> m) => RefundAnalysis(
    eligibility: Eligibility.fromWire(Read.strOrNull(m['eligibility'])),
    summary: Read.str(m['summary']),
    requiredInformation: Read.strings(m['requiredInformation']),
    missingInformation: Read.strings(m['missingInformation']),
    draftMessage: Read.str(m['draftMessage']),
  );
}

class RefundRequest {
  const RefundRequest({
    required this.id,
    required this.merchant,
    required this.reason,
    required this.createdAt,
    this.orderReference,
    this.purchaseDate,
    this.amountMinor,
    this.currency = AppConstants.defaultCurrency,
    this.policyText,
    this.analysis,
    this.status = RefundStatus.draft,
    this.linkedOrderId,
  });

  final String id;
  final String merchant;
  final String reason;
  final DateTime createdAt;
  final String? orderReference;
  final DateTime? purchaseDate;
  final int? amountMinor;
  final String currency;
  final String? policyText;
  final RefundAnalysis? analysis;
  final RefundStatus status;

  /// Set when the request concerns a FLOWMINT order paid through PayPal.
  final String? linkedOrderId;

  Map<String, dynamic> toMap() => {
    'merchant': merchant,
    'reason': reason,
    'orderReference': orderReference,
    'purchaseDate': purchaseDate == null
        ? null
        : Timestamp.fromDate(purchaseDate!),
    'amountMinor': amountMinor,
    'currency': currency,
    'policyText': policyText,
    'analysis': analysis?.toMap(),
    'status': status.name,
    'linkedOrderId': linkedOrderId,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory RefundRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return RefundRequest(
      id: doc.id,
      merchant: Read.str(m['merchant']),
      reason: Read.str(m['reason']),
      createdAt: Read.date(m['createdAt']) ?? DateTime.now(),
      orderReference: Read.strOrNull(m['orderReference']),
      purchaseDate: Read.date(m['purchaseDate']),
      amountMinor: m['amountMinor'] == null
          ? null
          : Read.integer(m['amountMinor']),
      currency: Read.str(m['currency'], AppConstants.defaultCurrency),
      policyText: Read.strOrNull(m['policyText']),
      analysis: m['analysis'] is Map
          ? RefundAnalysis.fromMap(Read.map(m['analysis']))
          : null,
      status: RefundStatus.fromWire(Read.strOrNull(m['status'])),
      linkedOrderId: Read.strOrNull(m['linkedOrderId']),
    );
  }
}

/// Values prepared by the assistant to prefill the refund editor.
class RefundDraft {
  const RefundDraft({
    this.merchant,
    this.orderReference,
    this.amountMinor,
    this.reason,
    this.receiptDocument,
    this.sourceMessageId,
  });

  final String? merchant;
  final String? orderReference;
  final int? amountMinor;
  final String? reason;
  final AiDocument? receiptDocument;
  final String? sourceMessageId;
}

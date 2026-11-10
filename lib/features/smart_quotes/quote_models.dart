import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/json_read.dart';

enum QuoteStatus {
  draft('Draft'),
  sent('Sent'),
  accepted('Accepted'),
  paid('Paid'),
  declined('Declined');

  const QuoteStatus(this.label);
  final String label;

  static QuoteStatus fromWire(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => draft);
}

class QuoteLineItem {
  const QuoteLineItem({
    required this.description,
    required this.quantity,
    required this.unitPriceMinor,
  });

  final String description;
  final double quantity;
  final int unitPriceMinor;

  int get amountMinor => (quantity * unitPriceMinor).round();

  Map<String, dynamic> toMap() => {
    'description': description,
    'quantity': quantity,
    'unitPriceMinor': unitPriceMinor,
  };

  factory QuoteLineItem.fromMap(Map<String, dynamic> m) => QuoteLineItem(
    description: Read.str(m['description']),
    quantity: Read.number(m['quantity']) ?? 1,
    unitPriceMinor: Read.integer(m['unitPriceMinor']),
  );
}

/// Milestone payment state, tracked by the freelancer. A milestone is never
/// "PayPal-confirmed": quotation payments happen outside FLOWMINT checkout.
enum MilestoneStatus {
  unpaid('Unpaid'),
  pending('Pending'),
  paid('Paid · marked by you');

  const MilestoneStatus(this.label);
  final String label;

  MilestoneStatus get next => values[(index + 1) % values.length];
}

class QuoteMilestone {
  const QuoteMilestone({
    required this.title,
    required this.percent,
    this.status = MilestoneStatus.unpaid,
  });

  final String title;
  final int percent;
  final MilestoneStatus status;

  bool get paid => status == MilestoneStatus.paid;

  QuoteMilestone copyWith({MilestoneStatus? status}) => QuoteMilestone(
    title: title,
    percent: percent,
    status: status ?? this.status,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'percent': percent,
    'status': status.name,
  };

  factory QuoteMilestone.fromMap(Map<String, dynamic> m) => QuoteMilestone(
    title: Read.str(m['title']),
    percent: Read.integer(m['percent']),
    status: MilestoneStatus.values.firstWhere(
      (s) => s.name == m['status'],
      // Records saved before the three-state model stored a boolean.
      orElse: () => Read.boolean(m['paid'])
          ? MilestoneStatus.paid
          : MilestoneStatus.unpaid,
    ),
  );
}

class QuoteTotals {
  const QuoteTotals({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
}

abstract final class QuoteCalculator {
  static QuoteTotals totals(
    List<QuoteLineItem> items, {
    double taxRatePercent = 0,
    int discountMinor = 0,
  }) {
    final subtotal = items.fold<int>(0, (s, i) => s + i.amountMinor);
    final discount = discountMinor.clamp(0, subtotal);
    final taxable = subtotal - discount;
    final tax = (taxable * taxRatePercent / 100).round();
    return QuoteTotals(
      subtotalMinor: subtotal,
      discountMinor: discount,
      taxMinor: tax,
      totalMinor: taxable + tax,
    );
  }

  /// Amount due per milestone. The last milestone absorbs rounding so the
  /// amounts always add up to [totalMinor] when percentages sum to 100.
  static List<int> milestoneAmounts(int totalMinor, List<int> percents) {
    if (percents.isEmpty) return const [];
    final amounts = [for (final p in percents) (totalMinor * p / 100).floor()];
    if (percents.fold<int>(0, (s, p) => s + p) == 100) {
      final allocated = amounts.fold<int>(0, (s, a) => s + a);
      amounts[amounts.length - 1] += totalMinor - allocated;
    }
    return amounts;
  }
}

class Quotation {
  const Quotation({
    required this.id,
    required this.number,
    required this.clientName,
    required this.projectTitle,
    required this.items,
    required this.createdAt,
    this.clientEmail,
    this.clientCompany,
    this.projectDescription = '',
    this.currency = AppConstants.defaultCurrency,
    this.taxRatePercent = 0,
    this.discountMinor = 0,
    this.milestones = const [],
    this.validUntil,
    this.notes = '',
    this.status = QuoteStatus.draft,
    this.aiSuggested = false,
  });

  final String id;
  final String number;
  final String clientName;
  final String? clientEmail;
  final String? clientCompany;
  final String projectTitle;
  final String projectDescription;
  final String currency;
  final List<QuoteLineItem> items;
  final double taxRatePercent;
  final int discountMinor;
  final List<QuoteMilestone> milestones;
  final DateTime? validUntil;
  final String notes;
  final QuoteStatus status;
  final bool aiSuggested;
  final DateTime createdAt;

  QuoteTotals get totals => QuoteCalculator.totals(
    items,
    taxRatePercent: taxRatePercent,
    discountMinor: discountMinor,
  );

  List<int> get milestoneAmounts => QuoteCalculator.milestoneAmounts(
    totals.totalMinor,
    [for (final m in milestones) m.percent],
  );

  int get paidMinor {
    final amounts = milestoneAmounts;
    var sum = 0;
    for (var i = 0; i < milestones.length; i++) {
      if (milestones[i].paid) sum += amounts[i];
    }
    return sum;
  }

  Map<String, dynamic> toMap() => {
    'number': number,
    'clientName': clientName,
    'clientEmail': clientEmail,
    'clientCompany': clientCompany,
    'projectTitle': projectTitle,
    'projectDescription': projectDescription,
    'currency': currency,
    'items': items.map((i) => i.toMap()).toList(),
    'taxRatePercent': taxRatePercent,
    'discountMinor': discountMinor,
    'milestones': milestones.map((m) => m.toMap()).toList(),
    'validUntil': validUntil == null ? null : Timestamp.fromDate(validUntil!),
    'notes': notes,
    'status': status.name,
    'aiSuggested': aiSuggested,
    'totalMinor': totals.totalMinor,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory Quotation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Quotation(
      id: doc.id,
      number: Read.str(m['number']),
      clientName: Read.str(m['clientName']),
      clientEmail: Read.strOrNull(m['clientEmail']),
      clientCompany: Read.strOrNull(m['clientCompany']),
      projectTitle: Read.str(m['projectTitle']),
      projectDescription: Read.str(m['projectDescription']),
      currency: Read.str(m['currency'], AppConstants.defaultCurrency),
      items: Read.maps(m['items']).map(QuoteLineItem.fromMap).toList(),
      taxRatePercent: Read.number(m['taxRatePercent']) ?? 0,
      discountMinor: Read.integer(m['discountMinor']),
      milestones: Read.maps(
        m['milestones'],
      ).map(QuoteMilestone.fromMap).toList(),
      validUntil: Read.date(m['validUntil']),
      notes: Read.str(m['notes']),
      status: QuoteStatus.fromWire(Read.strOrNull(m['status'])),
      aiSuggested: Read.boolean(m['aiSuggested']),
      createdAt: Read.date(m['createdAt']) ?? DateTime.now(),
    );
  }

  Quotation copyWith({QuoteStatus? status, List<QuoteMilestone>? milestones}) =>
      Quotation(
        id: id,
        number: number,
        clientName: clientName,
        clientEmail: clientEmail,
        clientCompany: clientCompany,
        projectTitle: projectTitle,
        projectDescription: projectDescription,
        currency: currency,
        items: items,
        taxRatePercent: taxRatePercent,
        discountMinor: discountMinor,
        milestones: milestones ?? this.milestones,
        validUntil: validUntil,
        notes: notes,
        status: status ?? this.status,
        aiSuggested: aiSuggested,
        createdAt: createdAt,
      );
}

/// A quotation drafted by Gemini (or prefilled by the assistant). Serialisable
/// so it can be stored with the assistant message that produced it.
class QuoteSeed {
  const QuoteSeed({
    this.clientName,
    this.projectTitle,
    this.projectDescription,
    this.items = const [],
    this.milestones = const [],
    this.notes,
    this.aiSuggested = false,
    this.sourceMessageId,
  });

  final String? clientName;
  final String? projectTitle;
  final String? projectDescription;
  final List<QuoteLineItem> items;
  final List<QuoteMilestone> milestones;
  final String? notes;
  final bool aiSuggested;
  final String? sourceMessageId;

  int get totalMinor => QuoteCalculator.totals(items).totalMinor;

  QuoteSeed withSource(String messageId) => QuoteSeed(
    clientName: clientName,
    projectTitle: projectTitle,
    projectDescription: projectDescription,
    items: items,
    milestones: milestones,
    notes: notes,
    aiSuggested: aiSuggested,
    sourceMessageId: messageId,
  );

  Map<String, dynamic> toJson() => {
    'clientName': clientName,
    'projectTitle': projectTitle,
    'projectDescription': projectDescription,
    'items': items.map((i) => i.toMap()).toList(),
    'milestones': milestones.map((m) => m.toMap()).toList(),
    'notes': notes,
    'aiSuggested': aiSuggested,
  };

  factory QuoteSeed.fromJson(Map<String, dynamic> j) => QuoteSeed(
    clientName: Read.strOrNull(j['clientName']),
    projectTitle: Read.strOrNull(j['projectTitle']),
    projectDescription: Read.strOrNull(j['projectDescription']),
    items: Read.maps(j['items']).map(QuoteLineItem.fromMap).toList(),
    milestones: Read.maps(j['milestones']).map(QuoteMilestone.fromMap).toList(),
    notes: Read.strOrNull(j['notes']),
    aiSuggested: Read.boolean(j['aiSuggested']),
  );
}

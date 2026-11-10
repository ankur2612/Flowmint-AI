import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import '../../core/utils/json_read.dart';

enum SplitMode { equal, custom }

class SplitParticipant {
  const SplitParticipant({
    required this.id,
    required this.name,
    required this.shareMinor,
    this.settled = false,
    this.isOrganizer = false,
  });

  final String id;
  final String name;
  final int shareMinor;

  /// Marked by the organiser when they have received this share. This is
  /// user-tracked, not a verified transfer.
  final bool settled;

  /// The person who paid the bill and is owed by everyone else.
  final bool isOrganizer;

  SplitParticipant copyWith({String? name, int? shareMinor, bool? settled}) =>
      SplitParticipant(
        id: id,
        name: name ?? this.name,
        shareMinor: shareMinor ?? this.shareMinor,
        settled: settled ?? this.settled,
        isOrganizer: isOrganizer,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'shareMinor': shareMinor,
    'settled': settled,
    'isOrganizer': isOrganizer,
  };

  factory SplitParticipant.fromMap(Map<String, dynamic> m) => SplitParticipant(
    id: Read.str(m['id']),
    name: Read.str(m['name']),
    shareMinor: Read.integer(m['shareMinor']),
    settled: Read.boolean(m['settled']),
    isOrganizer: Read.boolean(m['isOrganizer']),
  );
}

class ExpenseGroup {
  const ExpenseGroup({
    required this.id,
    required this.title,
    required this.totalMinor,
    required this.currency,
    required this.mode,
    required this.participants,
    required this.createdAt,
    this.merchant,
    this.breakdown,
  });

  final String id;
  final String title;
  final int totalMinor;
  final String currency;
  final SplitMode mode;
  final List<SplitParticipant> participants;
  final DateTime createdAt;
  final String? merchant;

  /// Optional subtotal/tax/tip/discount the total was computed from.
  final BillBreakdown? breakdown;

  Iterable<SplitParticipant> get debtors =>
      participants.where((p) => !p.isOrganizer);

  int get owedMinor => debtors.fold(0, (s, p) => s + p.shareMinor);

  int get receivedMinor =>
      debtors.where((p) => p.settled).fold(0, (s, p) => s + p.shareMinor);

  int get outstandingMinor => owedMinor - receivedMinor;

  bool get isSettled => debtors.every((p) => p.settled);

  ExpenseGroup copyWith({List<SplitParticipant>? participants}) => ExpenseGroup(
    id: id,
    title: title,
    totalMinor: totalMinor,
    currency: currency,
    mode: mode,
    participants: participants ?? this.participants,
    createdAt: createdAt,
    merchant: merchant,
    breakdown: breakdown,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'totalMinor': totalMinor,
    'currency': currency,
    'mode': mode.name,
    'participants': participants.map((p) => p.toMap()).toList(),
    'merchant': merchant,
    'breakdown': breakdown?.toMap(),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory ExpenseGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return ExpenseGroup(
      id: doc.id,
      title: Read.str(m['title'], 'Shared expense'),
      totalMinor: Read.integer(m['totalMinor']),
      currency: Read.str(m['currency'], AppConstants.defaultCurrency),
      mode: Read.str(m['mode']) == 'custom'
          ? SplitMode.custom
          : SplitMode.equal,
      participants: Read.maps(
        m['participants'],
      ).map(SplitParticipant.fromMap).toList(),
      createdAt: Read.date(m['createdAt']) ?? DateTime.now(),
      merchant: Read.strOrNull(m['merchant']),
      breakdown: m['breakdown'] is Map
          ? BillBreakdown.fromMap(Read.map(m['breakdown']))
          : null,
    );
  }
}

/// Values prepared by the assistant (or a scanned bill) to prefill the
/// split editor. The user reviews and edits everything before saving.
class SplitDraft {
  const SplitDraft({
    this.title,
    this.totalMinor,
    this.participantNames = const [],
    this.participantCount,
    this.sourceMessageId,
    this.billDocument,
  });

  final String? title;
  final int? totalMinor;
  final List<String> participantNames;
  final int? participantCount;
  final String? sourceMessageId;
  final AiDocument? billDocument;
}

/// How a bill total is composed. All values are minor units.
class BillBreakdown {
  const BillBreakdown({
    required this.subtotalMinor,
    this.taxMinor = 0,
    this.tipMinor = 0,
    this.discountMinor = 0,
  });

  final int subtotalMinor;
  final int taxMinor;
  final int tipMinor;
  final int discountMinor;

  /// Subtotal + tax + tip − discount, never negative.
  int get totalMinor {
    final t = subtotalMinor + taxMinor + tipMinor - discountMinor;
    return t < 0 ? 0 : t;
  }

  Map<String, dynamic> toMap() => {
    'subtotalMinor': subtotalMinor,
    'taxMinor': taxMinor,
    'tipMinor': tipMinor,
    'discountMinor': discountMinor,
  };

  factory BillBreakdown.fromMap(Map<String, dynamic> m) => BillBreakdown(
    subtotalMinor: Read.integer(m['subtotalMinor']),
    taxMinor: Read.integer(m['taxMinor']),
    tipMinor: Read.integer(m['tipMinor']),
    discountMinor: Read.integer(m['discountMinor']),
  );
}

abstract final class SplitCalculator {
  /// Splits [totalMinor] into [count] shares that differ by at most one minor
  /// unit and always add up exactly to the total.
  static List<int> equalShares(int totalMinor, int count) {
    if (count <= 0) return const [];
    final base = totalMinor ~/ count;
    final remainder = totalMinor % count;
    return List.generate(count, (i) => base + (i < remainder ? 1 : 0));
  }

  /// Positive when custom shares fall short of the total, negative when they
  /// exceed it, zero when they balance.
  static int unallocated(int totalMinor, Iterable<int> shares) =>
      totalMinor - shares.fold(0, (s, v) => s + v);
}

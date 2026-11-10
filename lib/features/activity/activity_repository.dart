import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/utils/json_read.dart';
import '../../core/widgets/app_card.dart';

enum ActivityType {
  shoppingOrder(
    'shopping_order',
    'Shopping order',
    Icons.shopping_bag_outlined,
  ),
  donation('donation', 'Donation', Icons.volunteer_activism_outlined),
  refund('refund', 'Refund', Icons.undo_rounded),
  quotation('quotation', 'Quotation', Icons.request_quote_outlined),
  expenseSplit('expense_split', 'Expense split', Icons.call_split_rounded);

  const ActivityType(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static ActivityType? fromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum ActivityStatus {
  pending('Pending', Tone.warning),
  completed('Completed', Tone.positive),
  failed('Failed', Tone.danger),
  cancelled('Cancelled', Tone.neutral);

  const ActivityStatus(this.label, this.tone);
  final String label;
  final Tone tone;

  static ActivityStatus fromWire(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => pending);
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.verified,
    this.amountMinor,
    this.currency = 'INR',
    this.route,
    this.createdAt,
  });

  final String id;
  final ActivityType type;
  final ActivityStatus status;
  final String title;
  final String subtitle;

  /// True when written by the backend after PayPal confirmation; false for
  /// records the user tracks themselves (splits, quotations, refund drafts).
  final bool verified;
  final int? amountMinor;
  final String currency;
  final String? route;
  final DateTime? createdAt;

  /// Whether the entry represents money movement verified through PayPal.
  bool get isPayment =>
      verified &&
      (type == ActivityType.shoppingOrder || type == ActivityType.donation);

  static ActivityEntry? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    if (m == null) return null;
    final type = ActivityType.fromWire(Read.strOrNull(m['type']));
    if (type == null) return null;
    return ActivityEntry(
      id: doc.id,
      type: type,
      status: ActivityStatus.fromWire(Read.strOrNull(m['status'])),
      title: Read.str(m['title']),
      subtitle: Read.str(m['subtitle']),
      verified: Read.str(m['source']) == 'server',
      amountMinor: m['amountMinor'] == null
          ? null
          : Read.integer(m['amountMinor']),
      currency: Read.str(m['currency'], 'INR'),
      route: Read.strOrNull(m['route']),
      createdAt: Read.date(m['createdAt']),
    );
  }
}

/// Timeline of the user's financial activity. Client-tracked entries are
/// written here; PayPal-verified entries are written only by Cloud Functions
/// (enforced by Firestore rules).
class ActivityRepository extends UserScopedRepository {
  const ActivityRepository(super.userDoc);

  CollectionReference<Map<String, dynamic>> get _col => collection('activity');

  Stream<List<ActivityEntry>> watch({int limit = 200}) => !isSignedIn
      ? const Stream.empty()
      : _col
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(
              (q) => q.docs
                  .map(ActivityEntry.fromDoc)
                  .whereType<ActivityEntry>()
                  .toList(),
            );

  Future<void> record({
    required ActivityType type,
    required String refId,
    required ActivityStatus status,
    required String title,
    required String subtitle,
    required String route,
    required DateTime createdAt,
    int? amountMinor,
    String currency = 'INR',
  }) {
    return _col.doc('${type.wire}_$refId').set({
      'type': type.wire,
      'status': status.name,
      'title': title,
      'subtitle': subtitle,
      'route': route,
      'amountMinor': amountMinor,
      'currency': currency,
      'source': 'client',
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> remove(ActivityType type, String refId) =>
      _col.doc('${type.wire}_$refId').delete();
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(userDocProvider)),
);

final activityProvider = StreamProvider.autoDispose<List<ActivityEntry>>(
  (ref) => ref.watch(activityRepositoryProvider).watch(),
);

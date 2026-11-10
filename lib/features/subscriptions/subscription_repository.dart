import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_providers.dart';
import '../../core/utils/json_read.dart';

enum BillingFrequency {
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  quarterly('Quarterly', 'quarter'),
  yearly('Yearly', 'year');

  const BillingFrequency(this.label, this.unit);
  final String label;
  final String unit;

  static BillingFrequency fromWire(String? v) =>
      values.firstWhere((f) => f.name == v, orElse: () => monthly);
}

const subscriptionCategories = [
  'Entertainment',
  'Music',
  'Productivity',
  'Cloud & storage',
  'News & reading',
  'Fitness',
  'Education',
  'Utilities',
  'Other',
];

DateTime _addMonths(DateTime d, int months) {
  final y = d.year + (d.month - 1 + months) ~/ 12;
  final m = (d.month - 1 + months) % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

/// A recurring expense the user tracks manually.
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.frequency,
    required this.nextRenewal,
    this.currency = AppConstants.defaultCurrency,
    this.category = 'Other',
    this.active = true,
    this.reminders = true,
  });

  final String id;
  final String name;
  final int amountMinor;
  final BillingFrequency frequency;
  final DateTime nextRenewal;
  final String currency;
  final String category;
  final bool active;
  final bool reminders;

  /// Cost normalised to one month.
  int get monthlyMinor => switch (frequency) {
    BillingFrequency.weekly => (amountMinor * 52 / 12).round(),
    BillingFrequency.monthly => amountMinor,
    BillingFrequency.quarterly => (amountMinor / 3).round(),
    BillingFrequency.yearly => (amountMinor / 12).round(),
  };

  int get annualMinor => switch (frequency) {
    BillingFrequency.weekly => amountMinor * 52,
    BillingFrequency.monthly => amountMinor * 12,
    BillingFrequency.quarterly => amountMinor * 4,
    BillingFrequency.yearly => amountMinor,
  };

  DateTime _advance(DateTime d) => switch (frequency) {
    BillingFrequency.weekly => d.add(const Duration(days: 7)),
    BillingFrequency.monthly => _addMonths(d, 1),
    BillingFrequency.quarterly => _addMonths(d, 3),
    BillingFrequency.yearly => _addMonths(d, 12),
  };

  /// The first renewal on or after [today], rolling a stale stored date
  /// forward by the billing period.
  DateTime upcomingRenewal(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    var d = DateTime(nextRenewal.year, nextRenewal.month, nextRenewal.day);
    var guard = 0;
    while (d.isBefore(day) && guard++ < 1000) {
      d = _advance(d);
    }
    return d;
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'amountMinor': amountMinor,
    'currency': currency,
    'frequency': frequency.name,
    'nextRenewal': Timestamp.fromDate(nextRenewal),
    'category': category,
    'active': active,
    'reminders': reminders,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory Subscription.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Subscription(
      id: doc.id,
      name: Read.str(m['name']),
      amountMinor: Read.integer(m['amountMinor']),
      currency: Read.str(m['currency'], AppConstants.defaultCurrency),
      frequency: BillingFrequency.fromWire(Read.strOrNull(m['frequency'])),
      nextRenewal: Read.date(m['nextRenewal']) ?? DateTime.now(),
      category: Read.str(m['category'], 'Other'),
      active: Read.boolean(m['active'], true),
      reminders: Read.boolean(m['reminders'], true),
    );
  }
}

class UpcomingRenewal {
  const UpcomingRenewal(this.subscription, this.date);
  final Subscription subscription;
  final DateTime date;
}

class SubscriptionSummary {
  const SubscriptionSummary({
    required this.monthlyMinor,
    required this.annualMinor,
    required this.activeCount,
    required this.byCategory,
    required this.upcoming,
  });

  final int monthlyMinor;
  final int annualMinor;
  final int activeCount;

  /// Monthly-equivalent spend per category, largest first.
  final List<MapEntry<String, int>> byCategory;

  /// Active renewals within the next [window] days, soonest first.
  final List<UpcomingRenewal> upcoming;

  static SubscriptionSummary compute(
    List<Subscription> all, {
    required DateTime today,
    int window = 7,
    String currency = AppConstants.defaultCurrency,
  }) {
    final active = all
        .where((s) => s.active && s.currency == currency)
        .toList();
    final categories = <String, int>{};
    for (final s in active) {
      categories[s.category] = (categories[s.category] ?? 0) + s.monthlyMinor;
    }
    final horizon = DateTime(today.year, today.month, today.day + window);
    final upcoming = [
      for (final s in active)
        if (!s.upcomingRenewal(today).isAfter(horizon))
          UpcomingRenewal(s, s.upcomingRenewal(today)),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return SubscriptionSummary(
      monthlyMinor: active.fold(0, (s, x) => s + x.monthlyMinor),
      annualMinor: active.fold(0, (s, x) => s + x.annualMinor),
      activeCount: active.length,
      byCategory: categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
      upcoming: upcoming,
    );
  }
}

class SubscriptionRepository extends UserScopedRepository {
  const SubscriptionRepository(super.userDoc);

  Stream<List<Subscription>> watchAll() => !isSignedIn
      ? const Stream.empty()
      : collection('subscriptions')
            .orderBy('name')
            .snapshots()
            .map((q) => q.docs.map(Subscription.fromDoc).toList());

  Future<List<Subscription>> fetchAll() async => (await collection(
    'subscriptions',
  ).get()).docs.map(Subscription.fromDoc).toList();

  Future<void> save(Subscription s) => s.id.isEmpty
      ? collection('subscriptions').add(s.toMap())
      // Merge keeps server-managed fields such as lastReminderFor.
      : collection(
          'subscriptions',
        ).doc(s.id).set(s.toMap(), SetOptions(merge: true));

  Future<void> delete(String id) =>
      collection('subscriptions').doc(id).delete();
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(userDocProvider)),
);

final subscriptionsProvider = StreamProvider.autoDispose<List<Subscription>>(
  (ref) => ref.watch(subscriptionRepositoryProvider).watchAll(),
);

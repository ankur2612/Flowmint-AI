import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../activity/activity_repository.dart';
import '../smart_quotes/quote_models.dart';
import '../smart_quotes/quote_repository.dart';
import '../smart_split/split_repository.dart';
import '../subscriptions/subscription_repository.dart';

/// Dashboard figures derived only from the user's own records. Nothing here
/// is estimated or illustrative.
class HomeOverview {
  const HomeOverview({
    required this.paidThisMonthMinor,
    required this.paidCurrency,
    required this.paymentsThisMonth,
    required this.subscriptions,
    required this.owedToYouMinor,
    required this.awaitingFromClientsMinor,
    required this.recent,
  });

  /// PayPal-verified payments (orders and donations) completed this month.
  final int paidThisMonthMinor;

  /// Currency of [paidThisMonthMinor]; amounts in other currencies are not
  /// added together.
  final String paidCurrency;
  final int paymentsThisMonth;
  final SubscriptionSummary subscriptions;

  /// Unsettled shares in the user's splits (user-tracked).
  final int owedToYouMinor;

  /// Unpaid milestones on sent or accepted quotations (user-tracked).
  final int awaitingFromClientsMinor;
  final List<ActivityEntry> recent;

  bool get isEmpty =>
      recent.isEmpty &&
      subscriptions.activeCount == 0 &&
      owedToYouMinor == 0 &&
      awaitingFromClientsMinor == 0;
}

final homeOverviewProvider = Provider.autoDispose<AsyncValue<HomeOverview>>((
  ref,
) {
  final activity = ref.watch(activityProvider);
  final subs = ref.watch(subscriptionsProvider);
  final splits = ref.watch(expenseGroupsProvider);
  final quotes = ref.watch(quotationsProvider);

  for (final v in [activity, subs, splits, quotes]) {
    if (v.hasError) {
      return AsyncValue.error(v.error!, v.stackTrace ?? StackTrace.current);
    }
  }
  if (!activity.hasValue ||
      !subs.hasValue ||
      !splits.hasValue ||
      !quotes.hasValue) {
    return const AsyncValue.loading();
  }

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final paidAll = activity.value!.where(
    (e) =>
        e.isPayment &&
        e.status == ActivityStatus.completed &&
        e.createdAt != null &&
        !e.createdAt!.isBefore(monthStart),
  );
  final currency =
      paidAll.any((e) => e.currency == AppConstants.defaultCurrency) ||
          paidAll.isEmpty
      ? AppConstants.defaultCurrency
      : paidAll.first.currency;
  final paid = paidAll.where((e) => e.currency == currency);

  return AsyncValue.data(
    HomeOverview(
      paidThisMonthMinor: paid.fold(0, (s, e) => s + (e.amountMinor ?? 0)),
      paidCurrency: currency,
      paymentsThisMonth: paid.length,
      subscriptions: SubscriptionSummary.compute(subs.value!, today: now),
      owedToYouMinor: splits.value!.fold(0, (s, g) => s + g.outstandingMinor),
      awaitingFromClientsMinor: quotes.value!
          .where(
            (q) =>
                q.status == QuoteStatus.sent ||
                q.status == QuoteStatus.accepted,
          )
          .fold(0, (s, q) => s + q.totals.totalMinor - q.paidMinor),
      recent: activity.value!.take(5).toList(),
    ),
  );
});

import 'package:flowmint_ai/core/utils/money.dart';
import 'package:flowmint_ai/features/smart_quotes/quote_models.dart';
import 'package:flowmint_ai/features/smart_split/split_models.dart';
import 'package:flowmint_ai/features/subscriptions/subscription_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parseToMinor', () {
    test('parses formatted user input into minor units', () {
      expect(Money.parseToMinor('2,400'), 240000);
      expect(Money.parseToMinor('₹2400.5'), 240050);
      expect(Money.parseToMinor('0.99'), 99);
    });

    test('rejects malformed, negative and out-of-range input', () {
      expect(Money.parseToMinor(''), isNull);
      expect(Money.parseToMinor('-50'), isNull);
      expect(Money.parseToMinor('10.555'), isNull);
      expect(Money.parseToMinor('1.2.3'), isNull);
      expect(Money.parseToMinor('99999999'), isNull);
    });

    test('fromMajor rejects non-positive AI values', () {
      expect(Money.fromMajor(600), 60000);
      expect(Money.fromMajor(0), isNull);
      expect(Money.fromMajor(-1), isNull);
      expect(Money.fromMajor(double.nan), isNull);
    });
  });

  group('SplitCalculator', () {
    test('splits ₹2,400 between four people as ₹600 each', () {
      expect(SplitCalculator.equalShares(240000, 4), [
        60000,
        60000,
        60000,
        60000,
      ]);
    });

    test('distributes indivisible remainders without losing a paisa', () {
      final shares = SplitCalculator.equalShares(100000, 3);
      expect(shares, [33334, 33333, 33333]);
      expect(shares.reduce((a, b) => a + b), 100000);
    });

    test('reports unallocated amount for custom splits', () {
      expect(SplitCalculator.unallocated(1000, [400, 500]), 100);
      expect(SplitCalculator.unallocated(1000, [600, 500]), -100);
      expect(SplitCalculator.unallocated(1000, [500, 500]), 0);
    });

    test(
      'tracks outstanding amounts only for people who owe the organiser',
      () {
        final group = ExpenseGroup(
          id: 'g',
          title: 'Dinner',
          totalMinor: 240000,
          currency: 'INR',
          mode: SplitMode.equal,
          createdAt: DateTime(2026),
          participants: const [
            SplitParticipant(
              id: 'a',
              name: 'You',
              shareMinor: 60000,
              isOrganizer: true,
              settled: true,
            ),
            SplitParticipant(
              id: 'b',
              name: 'Asha',
              shareMinor: 60000,
              settled: true,
            ),
            SplitParticipant(id: 'c', name: 'Ravi', shareMinor: 60000),
            SplitParticipant(id: 'd', name: 'Meera', shareMinor: 60000),
          ],
        );
        expect(group.owedMinor, 180000);
        expect(group.receivedMinor, 60000);
        expect(group.outstandingMinor, 120000);
        expect(group.isSettled, isFalse);
      },
    );
  });

  group('QuoteCalculator', () {
    const items = [
      QuoteLineItem(
        description: 'Design',
        quantity: 1,
        unitPriceMinor: 2000000,
      ),
      QuoteLineItem(description: 'Pages', quantity: 5, unitPriceMinor: 800000),
    ];

    test('applies discount before tax', () {
      final t = QuoteCalculator.totals(
        items,
        taxRatePercent: 18,
        discountMinor: 1000000,
      );
      expect(t.subtotalMinor, 6000000);
      expect(t.discountMinor, 1000000);
      expect(t.taxMinor, 900000);
      expect(t.totalMinor, 5900000);
    });

    test('never discounts below zero', () {
      final t = QuoteCalculator.totals(items, discountMinor: 99999999);
      expect(t.totalMinor, 0);
    });

    test('milestone amounts always add up to the total', () {
      final amounts = QuoteCalculator.milestoneAmounts(100001, [33, 33, 34]);
      expect(amounts.reduce((a, b) => a + b), 100001);
    });
  });

  group('Subscription normalisation', () {
    Subscription sub(BillingFrequency f, int amount, DateTime next) =>
        Subscription(
          id: '',
          name: 'Service',
          amountMinor: amount,
          frequency: f,
          nextRenewal: next,
        );

    test('normalises billing frequencies to monthly and annual spend', () {
      final now = DateTime(2026, 11, 9);
      expect(sub(BillingFrequency.yearly, 120000, now).monthlyMinor, 10000);
      expect(sub(BillingFrequency.quarterly, 30000, now).monthlyMinor, 10000);
      expect(sub(BillingFrequency.weekly, 1200, now).annualMinor, 62400);
      expect(sub(BillingFrequency.monthly, 64900, now).annualMinor, 778800);
    });

    test('rolls stale renewal dates forward, clamping month ends', () {
      final s = sub(BillingFrequency.monthly, 100, DateTime(2026, 1, 31));
      expect(s.upcomingRenewal(DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    });

    test('summary counts only active subscriptions and upcoming renewals', () {
      final today = DateTime(2026, 11, 9);
      final summary = SubscriptionSummary.compute([
        sub(BillingFrequency.monthly, 64900, DateTime(2026, 11, 12)),
        sub(BillingFrequency.monthly, 11900, DateTime(2026, 11, 30)),
        Subscription(
          id: '',
          name: 'Paused',
          amountMinor: 50000,
          frequency: BillingFrequency.monthly,
          nextRenewal: DateTime(2026, 11, 10),
          active: false,
        ),
      ], today: today);
      expect(summary.activeCount, 2);
      expect(summary.monthlyMinor, 76800);
      expect(summary.upcoming.length, 1);
    });
  });

  group('BillBreakdown', () {
    test('total is subtotal + tax + tip - discount', () {
      const b = BillBreakdown(
        subtotalMinor: 200000,
        taxMinor: 36000,
        tipMinor: 20000,
        discountMinor: 16000,
      );
      expect(b.totalMinor, 240000);
      expect(SplitCalculator.equalShares(b.totalMinor, 4).first, 60000);
    });

    test('never goes negative', () {
      const b = BillBreakdown(subtotalMinor: 1000, discountMinor: 5000);
      expect(b.totalMinor, 0);
    });
  });

  group('Quote milestones', () {
    test('cycle Unpaid -> Pending -> Paid', () {
      expect(MilestoneStatus.unpaid.next, MilestoneStatus.pending);
      expect(MilestoneStatus.pending.next, MilestoneStatus.paid);
    });

    test('only paid milestones count towards received amount', () {
      final q = Quotation(
        id: 'q',
        number: 'FM-1',
        clientName: 'Acme',
        projectTitle: 'Website',
        createdAt: DateTime(2026),
        items: const [
          QuoteLineItem(
            description: 'Build',
            quantity: 1,
            unitPriceMinor: 100000,
          ),
        ],
        milestones: const [
          QuoteMilestone(
            title: 'Advance',
            percent: 50,
            status: MilestoneStatus.paid,
          ),
          QuoteMilestone(
            title: 'Delivery',
            percent: 50,
            status: MilestoneStatus.pending,
          ),
        ],
      );
      expect(q.paidMinor, 50000);
    });

    test('reads quotations saved with the legacy paid flag', () {
      final m = QuoteMilestone.fromMap({
        'title': 'Advance',
        'percent': 50,
        'paid': true,
      });
      expect(m.status, MilestoneStatus.paid);
    });
  });
}

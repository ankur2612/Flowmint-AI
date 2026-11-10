import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/firebase_providers.dart';
import '../activity/activity_repository.dart';
import 'quote_models.dart';

class QuoteRepository extends UserScopedRepository {
  const QuoteRepository(super.userDoc, this._activity);
  final ActivityRepository _activity;

  Stream<List<Quotation>> watchAll() => !isSignedIn
      ? const Stream.empty()
      : collection('quotations')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((q) => q.docs.map(Quotation.fromDoc).toList());

  Stream<Quotation?> watch(String id) => !isSignedIn
      ? const Stream.empty()
      : collection('quotations')
            .doc(id)
            .snapshots()
            .map((s) => s.exists ? Quotation.fromDoc(s) : null);

  Future<Quotation?> fetch(String id) async {
    final s = await collection('quotations').doc(id).get();
    return s.exists ? Quotation.fromDoc(s) : null;
  }

  /// Human-readable quotation number, e.g. FM-20261109-4821.
  String newNumber() {
    final now = DateTime.now();
    final suffix = (now.microsecondsSinceEpoch % 10000).toString().padLeft(
      4,
      '0',
    );
    return 'FM-${DateFormat('yyyyMMdd').format(now)}-$suffix';
  }

  /// Creates the quotation when [q.id] is empty, otherwise updates it.
  Future<String> save(Quotation q) async {
    final ref = q.id.isEmpty
        ? collection('quotations').doc()
        : collection('quotations').doc(q.id);
    await ref.set(q.toMap());
    await _syncActivity(Quotation.fromDoc(await ref.get()));
    return ref.id;
  }

  Future<void> setStatus(Quotation q, QuoteStatus status) =>
      save(q.copyWith(status: status));

  Future<void> setMilestoneStatus(
    Quotation q,
    int index,
    MilestoneStatus status,
  ) {
    final milestones = [
      for (var i = 0; i < q.milestones.length; i++)
        i == index ? q.milestones[i].copyWith(status: status) : q.milestones[i],
    ];
    final allPaid = milestones.isNotEmpty && milestones.every((m) => m.paid);
    return save(
      q.copyWith(
        milestones: milestones,
        status: allPaid
            ? QuoteStatus.paid
            : (q.status == QuoteStatus.paid ? QuoteStatus.accepted : q.status),
      ),
    );
  }

  Future<void> delete(String id) async {
    await collection('quotations').doc(id).delete();
    await _activity.remove(ActivityType.quotation, id);
  }

  Future<void> _syncActivity(Quotation q) => _activity.record(
    type: ActivityType.quotation,
    refId: q.id,
    status: switch (q.status) {
      QuoteStatus.paid => ActivityStatus.completed,
      QuoteStatus.declined => ActivityStatus.cancelled,
      _ => ActivityStatus.pending,
    },
    title: '${q.projectTitle} · ${q.clientName}',
    subtitle: '${q.number} · ${q.status.label}',
    route: '/quotes/${q.id}',
    createdAt: q.createdAt,
    amountMinor: q.totals.totalMinor,
    currency: q.currency,
  );
}

final quoteRepositoryProvider = Provider<QuoteRepository>(
  (ref) => QuoteRepository(
    ref.watch(userDocProvider),
    ref.watch(activityRepositoryProvider),
  ),
);

final quotationsProvider = StreamProvider.autoDispose<List<Quotation>>(
  (ref) => ref.watch(quoteRepositoryProvider).watchAll(),
);

final quotationProvider = StreamProvider.autoDispose.family<Quotation?, String>(
  (ref, id) => ref.watch(quoteRepositoryProvider).watch(id),
);

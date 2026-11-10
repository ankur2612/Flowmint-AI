import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/utils/money.dart';
import '../activity/activity_repository.dart';
import 'split_models.dart';

class SplitRepository extends UserScopedRepository {
  const SplitRepository(super.userDoc, this._activity);
  final ActivityRepository _activity;

  Stream<List<ExpenseGroup>> watchAll() => !isSignedIn
      ? const Stream.empty()
      : collection('expense_groups')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((q) => q.docs.map(ExpenseGroup.fromDoc).toList());

  Stream<ExpenseGroup?> watch(String id) => !isSignedIn
      ? const Stream.empty()
      : collection('expense_groups')
            .doc(id)
            .snapshots()
            .map((s) => s.exists ? ExpenseGroup.fromDoc(s) : null);

  Future<String> create(ExpenseGroup draft) async {
    final ref = collection('expense_groups').doc();
    await ref.set(draft.toMap());
    await _syncActivity(ExpenseGroup.fromDoc(await ref.get()));
    return ref.id;
  }

  Future<void> setSettled(
    ExpenseGroup group,
    String participantId,
    bool settled,
  ) async {
    final updated = group.copyWith(
      participants: [
        for (final p in group.participants)
          p.id == participantId ? p.copyWith(settled: settled) : p,
      ],
    );
    await collection('expense_groups').doc(group.id).update({
      'participants': updated.participants.map((p) => p.toMap()).toList(),
    });
    await _syncActivity(updated);
  }

  Future<void> delete(String id) async {
    await collection('expense_groups').doc(id).delete();
    await _activity.remove(ActivityType.expenseSplit, id);
  }

  Future<void> _syncActivity(ExpenseGroup g) {
    final debtors = g.debtors.length;
    final settled = g.debtors.where((p) => p.settled).length;
    return _activity.record(
      type: ActivityType.expenseSplit,
      refId: g.id,
      status: g.isSettled ? ActivityStatus.completed : ActivityStatus.pending,
      title: g.title,
      subtitle: debtors == 0
          ? 'Split with ${g.participants.length}'
          : '$settled of $debtors settled · ${Money.format(g.outstandingMinor, currency: g.currency)} outstanding',
      route: '/split/${g.id}',
      createdAt: g.createdAt,
      amountMinor: g.totalMinor,
      currency: g.currency,
    );
  }
}

final splitRepositoryProvider = Provider<SplitRepository>(
  (ref) => SplitRepository(
    ref.watch(userDocProvider),
    ref.watch(activityRepositoryProvider),
  ),
);

final expenseGroupsProvider = StreamProvider.autoDispose<List<ExpenseGroup>>(
  (ref) => ref.watch(splitRepositoryProvider).watchAll(),
);

final expenseGroupProvider = StreamProvider.autoDispose
    .family<ExpenseGroup?, String>(
      (ref, id) => ref.watch(splitRepositoryProvider).watch(id),
    );

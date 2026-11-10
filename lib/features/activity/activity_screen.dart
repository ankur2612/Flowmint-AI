import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/widgets/state_views.dart';
import 'activity_repository.dart';

enum ActivityFilter {
  all('All'),
  payments('Payments'),
  refunds('Refunds'),
  donations('Donations'),
  quotations('Quotations'),
  orders('Shopping orders'),
  settlements('Expense settlements');

  const ActivityFilter(this.label);
  final String label;

  bool matches(ActivityEntry e) => switch (this) {
    all => true,
    payments => e.isPayment,
    refunds => e.type == ActivityType.refund,
    donations => e.type == ActivityType.donation,
    quotations => e.type == ActivityType.quotation,
    orders => e.type == ActivityType.shoppingOrder,
    settlements => e.type == ActivityType.expenseSplit,
  };
}

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  ActivityFilter _filter = ActivityFilter.all;
  String _query = '';

  bool _matchesQuery(ActivityEntry e) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${e.title} ${e.subtitle} ${e.type.label} ${e.status.label}'
        .toLowerCase()
        .contains(q);
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat(
      day.year == today.year ? 'EEEE, d MMM' : 'd MMM yyyy',
    ).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.sm,
            ),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search activity',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              itemCount: ActivityFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
              itemBuilder: (_, i) {
                final f = ActivityFilter.values[i];
                return ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          const SizedBox(height: Space.xs),
          Expanded(
            child: activity.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorState(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(activityProvider),
              ),
              data: (all) {
                final list = all
                    .where((e) => _filter.matches(e) && _matchesQuery(e))
                    .toList();
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: all.isEmpty ? 'No activity yet' : 'Nothing here',
                    message: all.isEmpty
                        ? 'Payments, splits, quotations and refunds you make in FLOWMINT will appear here.'
                        : _query.isNotEmpty
                        ? 'Nothing matches "$_query".'
                        : 'No ${_filter.label.toLowerCase()} activity yet.',
                  );
                }
                final rows = <Widget>[];
                String? lastDay;
                for (final e in list) {
                  final day = e.createdAt == null
                      ? 'Earlier'
                      : _dayLabel(e.createdAt!);
                  if (day != lastDay) {
                    rows.add(
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Space.md,
                          bottom: Space.xs,
                        ),
                        child: Text(
                          day.toUpperCase(),
                          style: t.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    );
                    lastDay = day;
                  }
                  rows.add(
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: ActivityTile(entry: e),
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: () async => ref.invalidate(activityProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      0,
                      Space.gutter,
                      Space.xxl,
                    ),
                    children: rows,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final e = entry;
    return AppCard(
      onTap: () => showActivityDetail(context, e),
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          IconTile(e.type.icon, color: e.status.tone.color),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: t.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  e.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (e.amountMinor != null)
                Text(
                  Money.format(e.amountMinor!, currency: e.currency),
                  style: t.titleSmall,
                ),
              const SizedBox(height: 4),
              StatusBadge(e.status.label, tone: e.status.tone),
            ],
          ),
        ],
      ),
    );
  }
}

void showActivityDetail(BuildContext context, ActivityEntry e) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      final t = Theme.of(sheet).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconTile(e.type.icon, color: e.status.tone.color, size: 44),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.type.label.toUpperCase(),
                            style: t.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          Text(e.title, style: t.titleMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                LightPanel(
                  child: Column(
                    children: [
                      if (e.amountMinor != null)
                        DetailRow(
                          'Amount',
                          Money.format(e.amountMinor!, currency: e.currency),
                          emphasize: true,
                        ),
                      DetailRow('Status', e.status.label),
                      DetailRow('Details', e.subtitle),
                      DetailRow('Reference', e.id),
                      if (e.createdAt != null)
                        DetailRow(
                          'Date',
                          DateFormat('d MMM yyyy, h:mm a').format(e.createdAt!),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Icon(
                      e.verified
                          ? Icons.verified_rounded
                          : Icons.edit_note_rounded,
                      size: 16,
                      color: e.verified
                          ? AppColors.brand
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.verified
                            ? 'Status verified by PayPal through the FLOWMINT backend.'
                            : 'Tracked by you in FLOWMINT. No money moved through FLOWMINT for this record.',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (e.route != null) ...[
                  const SizedBox(height: Space.lg),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(sheet);
                      context.push(e.route!);
                    },
                    child: const Text('Open'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

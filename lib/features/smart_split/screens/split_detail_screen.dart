import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../profile/profile_repository.dart';
import '../split_models.dart';
import '../split_repository.dart';

class SplitDetailScreen extends ConsumerWidget {
  const SplitDetailScreen({super.key, required this.id});

  final String id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this split?'),
        content: const Text(
          'This removes the split and its settlement tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(splitRepositoryProvider).delete(id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(expenseGroupProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: group.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(message: friendlyError(e)),
        data: (g) => g == null
            ? const EmptyState(
                icon: Icons.call_split_rounded,
                title: 'Split not found',
                message: 'It may have been deleted.',
              )
            : _SplitView(group: g),
      ),
    );
  }
}

class _SplitView extends ConsumerWidget {
  const _SplitView({required this.group});

  final ExpenseGroup group;

  String _requestText(SplitParticipant p, String? paypalMe) {
    final amount = Money.format(p.shareMinor, currency: group.currency);
    final buffer = StringBuffer(
      'Hi ${p.name}, your share for "${group.title}" is $amount.',
    );
    if (paypalMe != null) {
      final major = (p.shareMinor / 100).toStringAsFixed(2);
      buffer.write(
        '\nYou can pay me on PayPal: https://paypal.me/$paypalMe/$major${group.currency}',
      );
    }
    buffer.write('\n— sent via FLOWMINT');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final g = group;
    final paypalMe = ref.watch(profileProvider).valueOrNull?.paypalMeUsername;
    final progress = g.owedMinor == 0 ? 1.0 : g.receivedMinor / g.owedMinor;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xs,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Text(g.title, style: t.headlineSmall),
        const SizedBox(height: Space.xxs),
        Text(
          '${DateFormat('d MMM yyyy').format(g.createdAt)} · '
          '${g.mode == SplitMode.equal ? 'Split equally' : 'Custom split'} · '
          '${g.participants.length} people',
          style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL BILL',
                style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: Space.xxs),
              Text(
                Money.format(g.totalMinor, currency: g.currency),
                style: t.displaySmall,
              ),
              if (g.breakdown != null) ...[
                const SizedBox(height: Space.xs),
                Text(
                  [
                    'Subtotal ${Money.format(g.breakdown!.subtotalMinor, currency: g.currency)}',
                    if (g.breakdown!.taxMinor > 0)
                      'Tax ${Money.format(g.breakdown!.taxMinor, currency: g.currency)}',
                    if (g.breakdown!.tipMinor > 0)
                      'Tip ${Money.format(g.breakdown!.tipMinor, currency: g.currency)}',
                    if (g.breakdown!.discountMinor > 0)
                      'Discount −${Money.format(g.breakdown!.discountMinor, currency: g.currency)}',
                  ].join('  ·  '),
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: Space.lg),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(value: v, minHeight: 6),
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Money.format(g.receivedMinor, currency: g.currency)} received',
                      style: t.bodySmall?.copyWith(color: AppColors.brand),
                    ),
                  ),
                  Text(
                    g.isSettled
                        ? 'All settled'
                        : '${Money.format(g.outstandingMinor, currency: g.currency)} outstanding',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        const SectionHeader('Contributions'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              for (final p in g.participants)
                _ParticipantRow(
                  participant: p,
                  currency: g.currency,
                  onToggle: p.isOrganizer
                      ? null
                      : (v) => ref
                            .read(splitRepositoryProvider)
                            .setSettled(g, p.id, v)
                            .catchError((Object e) {
                              if (context.mounted) {
                                showMessage(context, friendlyError(e));
                              }
                            }),
                  onRequest: p.isOrganizer || p.settled
                      ? null
                      : () => SharePlus.instance.share(
                          ShareParams(text: _requestText(p, paypalMe)),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                'Settlement status is tracked by you. FLOWMINT does not move money '
                'between participants; tap "Request" to send each person a payment '
                'request${paypalMe == null ? '. Add your PayPal.me username in Profile to include a PayPal link.' : ' with your PayPal.me link.'}',
                style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.currency,
    required this.onToggle,
    required this.onRequest,
  });

  final SplitParticipant participant;
  final String currency;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = participant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceHighest,
            child: Text(
              p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
              style: t.titleSmall,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: t.bodyLarge),
                const SizedBox(height: 2),
                p.isOrganizer
                    ? Text(
                        'Paid the bill',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    : StatusBadge(
                        p.settled ? 'Marked received' : 'Owes you',
                        tone: p.settled ? Tone.positive : Tone.warning,
                      ),
              ],
            ),
          ),
          Text(
            Money.format(p.shareMinor, currency: currency),
            style: t.titleSmall,
          ),
          if (onToggle != null) ...[
            const SizedBox(width: Space.xs),
            if (onRequest != null)
              IconButton(
                tooltip: 'Request payment',
                onPressed: onRequest,
                icon: const Icon(Icons.send_outlined, size: 19),
              ),
            Checkbox(value: p.settled, onChanged: (v) => onToggle!(v ?? false)),
          ],
        ],
      ),
    );
  }
}

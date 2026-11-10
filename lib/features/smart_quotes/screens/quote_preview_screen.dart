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
import '../quote_models.dart';
import '../quote_pdf.dart';
import '../quote_repository.dart';

Tone quoteTone(QuoteStatus s) => switch (s) {
  QuoteStatus.paid => Tone.positive,
  QuoteStatus.accepted => Tone.info,
  QuoteStatus.sent => Tone.warning,
  QuoteStatus.declined => Tone.danger,
  QuoteStatus.draft => Tone.neutral,
};

class QuotePreviewScreen extends ConsumerStatefulWidget {
  const QuotePreviewScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<QuotePreviewScreen> createState() => _QuotePreviewScreenState();
}

class _QuotePreviewScreenState extends ConsumerState<QuotePreviewScreen> {
  bool _exporting = false;

  Future<void> _share(Quotation q) async {
    setState(() => _exporting = true);
    try {
      final profile = ref.read(profileProvider).valueOrNull;
      final bytes = await buildQuotePdf(
        q,
        issuerName: (profile?.displayName.isNotEmpty ?? false)
            ? profile!.displayName
            : 'FLOWMINT user',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/pdf',
              name: '${q.number}.pdf',
            ),
          ],
          fileNameOverrides: ['${q.number}.pdf'],
          subject: 'Quotation ${q.number} — ${q.projectTitle}',
          text:
              'Quotation for ${q.projectTitle}: ${Money.format(q.totals.totalMinor, currency: q.currency)}',
        ),
      );
      if (q.status == QuoteStatus.draft) {
        await ref.read(quoteRepositoryProvider).setStatus(q, QuoteStatus.sent);
      }
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Could not export the quotation. ${friendlyError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete quotation?'),
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
    await ref.read(quoteRepositoryProvider).delete(widget.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(quotationProvider(widget.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotation'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/quotes/${widget.id}/edit'),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      body: quote.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(message: friendlyError(e)),
        data: (q) => q == null
            ? const EmptyState(
                icon: Icons.request_quote_outlined,
                title: 'Quotation not found',
                message: 'It may have been deleted.',
              )
            : _QuoteDocument(quote: q),
      ),
      bottomNavigationBar: quote.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.md,
                ),
                child: FilledButton.icon(
                  onPressed: _exporting ? null : () => _share(quote.value!),
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded, size: 19),
                  label: const Text('Export PDF & share'),
                ),
              ),
            ),
    );
  }
}

class _QuoteDocument extends ConsumerWidget {
  const _QuoteDocument({required this.quote});

  final Quotation quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final q = quote;
    final totals = q.totals;
    final amounts = q.milestoneAmounts;
    String money(int v) => Money.format(v, currency: q.currency);
    final repo = ref.read(quoteRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xs,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                q.number,
                style: t.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            PopupMenuButton<QuoteStatus>(
              tooltip: 'Change status',
              onSelected: (s) => repo.setStatus(q, s),
              itemBuilder: (_) => [
                for (final s in QuoteStatus.values)
                  PopupMenuItem(value: s, child: Text(s.label)),
              ],
              child: Row(
                children: [
                  StatusBadge(q.status.label, tone: quoteTone(q.status)),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(q.projectTitle, style: t.headlineSmall),
        const SizedBox(height: Space.xxs),
        Text(
          'For ${q.clientName}${q.clientCompany == null ? '' : ' · ${q.clientCompany}'}',
          style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        if (q.projectDescription.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text(q.projectDescription, style: t.bodyMedium),
        ],
        const SizedBox(height: Space.lg),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final i in q.items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.description, style: t.bodyMedium),
                            Text(
                              '${i.quantity == i.quantity.roundToDouble() ? i.quantity.toInt() : i.quantity} × ${money(i.unitPriceMinor)}',
                              style: t.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(money(i.amountMinor), style: t.titleSmall),
                    ],
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  children: [
                    DetailRow('Subtotal', money(totals.subtotalMinor)),
                    if (totals.discountMinor > 0)
                      DetailRow('Discount', '− ${money(totals.discountMinor)}'),
                    if (q.taxRatePercent > 0)
                      DetailRow(
                        'Tax (${q.taxRatePercent}%)',
                        money(totals.taxMinor),
                      ),
                    DetailRow(
                      'Total',
                      money(totals.totalMinor),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (q.milestones.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          SectionHeader(
            'Payment tracking · ${money(q.paidMinor)} of ${money(totals.totalMinor)} received',
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
            child: Column(
              children: [
                for (var i = 0; i < q.milestones.length; i++)
                  ListTile(
                    title: Text(
                      '${q.milestones[i].title} · ${q.milestones[i].percent}%',
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(
                          q.milestones[i].status.label,
                          tone: switch (q.milestones[i].status) {
                            MilestoneStatus.unpaid => Tone.neutral,
                            MilestoneStatus.pending => Tone.warning,
                            MilestoneStatus.paid => Tone.positive,
                          },
                        ),
                      ),
                    ),
                    trailing: Text(money(amounts[i]), style: t.titleSmall),
                    // Tap cycles Unpaid → Pending → Paid.
                    onTap: () => repo.setMilestoneStatus(
                      q,
                      i,
                      q.milestones[i].status.next,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Tap a milestone to update it: Unpaid → Pending → Paid. Statuses are tracked by you; client payments are not received through FLOWMINT.',
            style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
        if (q.validUntil != null || q.notes.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          if (q.validUntil != null)
            DetailRow(
              'Valid until',
              DateFormat('d MMM yyyy').format(q.validUntil!),
            ),
          if (q.notes.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              q.notes,
              style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ],
    );
  }
}

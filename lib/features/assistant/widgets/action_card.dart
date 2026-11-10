import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../refund/refund_models.dart';
import '../../shopping/cart_controller.dart';
import '../../shopping/catalog_repository.dart';
import '../../shopping/widgets/product_widgets.dart';
import '../../smart_quotes/quote_models.dart';
import '../../smart_split/split_models.dart';
import '../assistant_controller.dart';
import '../assistant_models.dart';

IconData intentIcon(AssistantIntent i) => switch (i) {
  AssistantIntent.smartSplit => Icons.call_split_rounded,
  AssistantIntent.refundAssistance => Icons.undo_rounded,
  AssistantIntent.impactGiving => Icons.volunteer_activism_outlined,
  AssistantIntent.smartQuotes => Icons.request_quote_outlined,
  AssistantIntent.subscriptionIntelligence => Icons.autorenew_rounded,
  AssistantIntent.aiShopping => Icons.shopping_bag_outlined,
  AssistantIntent.generalFinancialQuery => Icons.auto_awesome,
};

/// Structured workflow preview attached to an assistant reply. Cards only
/// navigate into module screens with prefilled drafts; every save or payment
/// happens there, after the user reviews it.
class ActionCard extends ConsumerWidget {
  const ActionCard({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = message.response;
    if (r == null || r.action == AssistantAction.none) {
      return const SizedBox.shrink();
    }
    final t = Theme.of(context).textTheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: child,
        ),
      ),
      child: AppCard(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(intentIcon(r.intent), size: 32),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(r.intent.label, style: t.titleSmall)),
                if (message.actionCompletedRoute != null)
                  const StatusBadge('Done', tone: Tone.positive)
                else if (r.requiresConfirmation)
                  const StatusBadge('Needs your approval', tone: Tone.warning),
              ],
            ),
            if (r.suggestedWorkflow.isNotEmpty)
              _Workflow(steps: r.suggestedWorkflow),
            if (r.missingInformation.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in r.missingInformation)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(
                        Icons.help_outline_rounded,
                        size: 15,
                        color: AppColors.warning,
                      ),
                      label: Text(m),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.sm),
            _body(context, ref, r),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, AssistantResponse r) {
    final done = message.actionCompletedRoute;
    final p = r.parameters;
    final image = ref
        .read(assistantControllerProvider.notifier)
        .documentFor(message.id);

    switch (r.action) {
      case AssistantAction.prepareSplit:
        final count =
            p.participantCount ??
            (p.participants.isEmpty ? null : p.participants.length);
        final share = p.amountMinor != null && count != null
            ? SplitCalculator.equalShares(p.amountMinor!, count).first
            : null;
        return _Section(
          rows: [
            if (p.title != null) ('For', p.title!),
            if (p.amountMinor != null)
              ('Total', Money.format(p.amountMinor!, currency: p.currency)),
            if (count != null) ('People', '$count'),
            if (share != null)
              ('Each pays', '≈ ${Money.format(share, currency: p.currency)}'),
          ],
          doneRoute: done,
          doneLabel: 'Split created',
          actionLabel: 'Review split',
          onAction: () => context.push(
            '/split/new',
            extra: SplitDraft(
              title: p.title,
              totalMinor: p.amountMinor,
              participantNames: p.participants,
              participantCount: count,
              sourceMessageId: message.id,
              billDocument: image,
            ),
          ),
        );

      case AssistantAction.draftQuotation:
        final a = message.attachment;
        final seed = a is QuoteDraftAttachment
            ? a.seed
            : QuoteSeed(
                clientName: p.clientName,
                projectDescription: p.projectDescription,
              );
        return _Section(
          rows: [
            if (seed.projectTitle != null) ('Project', seed.projectTitle!),
            if (seed.clientName != null) ('Client', seed.clientName!),
            if (seed.items.isNotEmpty) ('Line items', '${seed.items.length}'),
            if (seed.items.isNotEmpty)
              ('Suggested total', '${Money.format(seed.totalMinor)} + tax'),
          ],
          footnote: seed.aiSuggested
              ? 'Prices are AI suggestions — adjust them before sending.'
              : null,
          doneRoute: done,
          doneLabel: 'Quotation saved',
          actionLabel: seed.items.isEmpty
              ? 'Create quotation'
              : 'Open in editor',
          onAction: () =>
              context.push('/quotes/new', extra: seed.withSource(message.id)),
        );

      case AssistantAction.prepareRefundRequest:
        return _Section(
          rows: [
            if (p.merchant != null) ('Merchant', p.merchant!),
            if (p.orderReference != null) ('Order', p.orderReference!),
            if (p.amountMinor != null)
              ('Amount', Money.format(p.amountMinor!, currency: p.currency)),
            if (p.reason != null) ('Reason', p.reason!),
          ],
          doneRoute: done,
          doneLabel: 'Request saved',
          actionLabel: 'Prepare refund request',
          onAction: () => context.push(
            '/refunds/new',
            extra: RefundDraft(
              merchant: p.merchant,
              orderReference: p.orderReference,
              amountMinor: p.amountMinor,
              reason: p.reason,
              receiptDocument: image,
              sourceMessageId: message.id,
            ),
          ),
        );

      case AssistantAction.reviewSubscriptions:
        final a = message.attachment;
        if (a is! SubscriptionSnapshotAttachment || a.activeCount == 0) {
          return _Section(
            rows: const [],
            footnote:
                "You haven't added any active subscriptions yet. FLOWMINT only knows the subscriptions you add.",
            actionLabel: 'Add subscriptions',
            onAction: () => context.push('/subscriptions'),
          );
        }
        return _Section(
          rows: [
            ('Per month', Money.format(a.monthlyMinor, currency: a.currency)),
            ('Per year', Money.format(a.annualMinor, currency: a.currency)),
            ('Active', '${a.activeCount}'),
            if (a.topCategory != null) ('Largest category', a.topCategory!),
            if (a.nextRenewalName != null && a.nextRenewalDate != null)
              (
                'Next renewal',
                '${a.nextRenewalName} · ${DateFormat('d MMM').format(a.nextRenewalDate!)}',
              ),
          ],
          footnote: 'Based on the subscriptions you track in FLOWMINT.',
          actionLabel: 'Open Subscriptions',
          onAction: () => context.push('/subscriptions'),
        );

      case AssistantAction.prepareDonation:
        final a = message.attachment;
        final matches = a is CampaignMatchesAttachment
            ? a.matches
            : const <CampaignMatch>[];
        final amountQuery = p.amountMinor == null
            ? ''
            : '?amount=${p.amountMinor}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.amountMinor != null)
              DetailRow(
                'Amount',
                Money.format(p.amountMinor!, currency: p.currency),
                emphasize: true,
              ),
            if (p.cause != null) DetailRow('Cause', p.cause!),
            const SizedBox(height: Space.xs),
            if (matches.isEmpty)
              Text(
                p.cause == null
                    ? 'No donation campaigns are published yet.'
                    : 'No published campaign matches "${p.cause}" yet.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              )
            else
              for (final m in matches)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.volunteer_activism_outlined,
                    color: AppColors.brand,
                  ),
                  title: Text(m.title),
                  subtitle: Text(m.organization),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/giving/${m.id}$amountQuery'),
                ),
            const SizedBox(height: Space.xs),
            OutlinedButton(
              onPressed: () => context.push(
                '/giving${p.cause == null ? '' : '?cause=${Uri.encodeQueryComponent(p.cause!)}'}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Browse campaigns'),
            ),
          ],
        );

      case AssistantAction.searchProducts:
        final a = message.attachment;
        if (a is! ProductPicksAttachment) {
          return _Section(
            rows: const [],
            actionLabel: 'Open Shopping Agent',
            onAction: () => context.push('/shop'),
          );
        }
        return _ProductPicks(attachment: a);

      case AssistantAction.none:
        return const SizedBox.shrink();
    }
  }
}

class _Workflow extends StatelessWidget {
  const _Workflow({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(
          'How FLOWMINT will handle this',
          style: t.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}', style: t.labelSmall),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(steps[i], style: t.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.rows,
    required this.actionLabel,
    required this.onAction,
    this.doneRoute,
    this.doneLabel,
    this.footnote,
  });

  final List<(String, String)> rows;
  final String actionLabel;
  final VoidCallback onAction;
  final String? doneRoute;
  final String? doneLabel;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows) DetailRow(label, value),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text(
              footnote!,
              style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        const SizedBox(height: Space.sm),
        if (doneRoute != null)
          OutlinedButton.icon(
            onPressed: () => context.push(doneRoute!),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: AppColors.brand,
            ),
            label: Text('${doneLabel ?? 'Done'} · View'),
          )
        else
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }
}

class _ProductPicks extends ConsumerWidget {
  const _ProductPicks({required this.attachment});

  final ProductPicksAttachment attachment;

  Future<void> _addToCart(
    BuildContext context,
    WidgetRef ref,
    String productId,
  ) async {
    try {
      // Always add the current catalogue version, not the snapshot shown
      // in the conversation, so prices are never stale.
      final product = await ref
          .read(catalogRepositoryProvider)
          .fetch(productId);
      if (!context.mounted) return;
      if (product == null) {
        showMessage(context, 'This product is no longer available.');
        return;
      }
      final error = ref.read(cartProvider.notifier).add(product);
      showMessage(context, error ?? '${product.name} added to cart');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final a = attachment;
    final cartCount = ref.watch(cartProvider.select((c) => c.count));
    if (a.catalogueEmpty) {
      return Text(
        'The FLOWMINT catalogue has no products published yet, so there is nothing to recommend.',
        style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (a.summary != null)
          Text(
            a.summary!,
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        if (a.picks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'No catalogue products match this request.',
              style: t.bodySmall,
            ),
          ),
        for (final pick in a.picks)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => context.push('/shop/product/${pick.productId}'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImage(pick.imageUrl, size: 52),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pick.name,
                          style: t.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          Money.format(
                            pick.priceMinor,
                            currency: pick.currency,
                          ),
                          style: t.bodySmall?.copyWith(color: AppColors.brand),
                        ),
                        if (pick.reason.isNotEmpty)
                          Text(
                            pick.reason,
                            style: t.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add to cart',
                    onPressed: () => _addToCart(context, ref, pick.productId),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push(
                  '/shop?q=${Uri.encodeQueryComponent(a.query)}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Compare more'),
              ),
            ),
            if (cartCount > 0) ...[
              const SizedBox(width: Space.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push('/cart'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text('Review order ($cartCount)'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

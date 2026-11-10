import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/payments/checkout_flow.dart';
import '../../../core/payments/payment_models.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/state_views.dart';
import '../campaign_repository.dart';

class CampaignDetailScreen extends ConsumerStatefulWidget {
  const CampaignDetailScreen({
    super.key,
    required this.id,
    this.initialAmountMinor,
  });

  final String id;
  final int? initialAmountMinor;

  @override
  ConsumerState<CampaignDetailScreen> createState() =>
      _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> {
  late final _custom = TextEditingController(
    text: widget.initialAmountMinor == null
        ? ''
        : Money.toInput(widget.initialAmountMinor!),
  );
  late int? _amountMinor = widget.initialAmountMinor;

  /// Reused while the amount is unchanged so a retried checkout cannot
  /// create a second donation order.
  String _checkoutKey = const Uuid().v4();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _setAmount(int? minor) {
    if (minor == _amountMinor) return;
    setState(() {
      _amountMinor = minor;
      _checkoutKey = const Uuid().v4();
    });
  }

  Future<void> _donate(Campaign c) async {
    final amount = _amountMinor;
    if (amount == null || amount < c.minAmountMinor) {
      showMessage(
        context,
        'The minimum donation is ${Money.format(c.minAmountMinor, currency: c.currency)}.',
      );
      return;
    }
    final result = await CheckoutFlow.run(
      context,
      ref,
      review: PaymentReview(
        title: 'Donation',
        description: c.title,
        amountMinor: amount,
        currency: c.currency,
        recipient: c.recipientLabel,
        details: [
          ('Campaign', c.title),
          ('Organisation', c.organization),
          if (AppConstants.isSandbox)
            ('Environment', 'PayPal Sandbox · test funds'),
        ],
      ),
      request: DonationCheckoutRequest(
        _checkoutKey,
        campaignId: c.id,
        amountMinor: amount,
      ),
    );
    if (result == null || !mounted) return;
    if (result.status == PaymentStatus.cancelled) {
      showMessage(context, 'Donation cancelled. You have not been charged.');
      return;
    }
    setState(() => _checkoutKey = const Uuid().v4());
    context.push('/payments/donation/${result.recordId}');
  }

  @override
  Widget build(BuildContext context) {
    final campaign = ref.watch(campaignProvider(widget.id));
    return Scaffold(
      appBar: AppBar(),
      body: campaign.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(message: friendlyError(e)),
        data: (c) => c == null
            ? const EmptyState(
                icon: Icons.volunteer_activism_outlined,
                title: 'Campaign unavailable',
                message: 'This campaign is no longer active.',
              )
            : _buildBody(c),
      ),
      bottomNavigationBar: campaign.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.md,
                ),
                child: FilledButton(
                  onPressed: _amountMinor == null || campaign.value!.isDemo
                      ? null
                      : () => _donate(campaign.value!),
                  child: Text(
                    campaign.value!.isDemo
                        ? 'Demo campaign · donations disabled'
                        : _amountMinor == null
                        ? 'Choose an amount'
                        : 'Donate ${Money.format(_amountMinor!, currency: campaign.value!.currency)}',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(Campaign c) {
    final t = Theme.of(context).textTheme;
    final suggestions = c.suggestedAmountsMinor.isEmpty
        ? [c.minAmountMinor * 5, c.minAmountMinor * 10, c.minAmountMinor * 25]
        : c.suggestedAmountsMinor;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.xxl,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text(c.title, style: t.headlineSmall),
        const SizedBox(height: Space.xxs),
        Row(
          children: [
            Flexible(
              child: Text(
                c.organization,
                style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            if (c.organizationVerified) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.verified_rounded,
                size: 16,
                color: AppColors.brand,
              ),
            ],
          ],
        ),
        const SizedBox(height: Space.lg),
        if (c.isDemo)
          AppCard(
            child: Row(
              children: [
                const StatusBadge('DEMO', tone: Tone.info),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Sample campaign for demonstration. Target'
                    '${c.goalMinor == null ? '' : ' ${Money.format(c.goalMinor!, currency: c.currency)}'} '
                    'is illustrative; no money has been raised and donations are disabled.',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (c.goalMinor != null && c.goalMinor! > 0)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Money.format(c.raisedMinor, currency: c.currency),
                  style: t.headlineSmall,
                ),
                Text(
                  'raised through FLOWMINT of ${Money.format(c.goalMinor!, currency: c.currency)} · ${c.donorCount} donations',
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: Space.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: (c.raisedMinor / c.goalMinor!).clamp(0, 1),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Only PayPal-confirmed donations made in FLOWMINT are counted.',
                  style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.lg),
        Text(c.description, style: t.bodyMedium),
        const SizedBox(height: Space.xl),
        const SectionHeader('Choose an amount'),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final s in suggestions)
              ChoiceChip(
                label: Text(Money.format(s, currency: c.currency)),
                selected: _amountMinor == s,
                onSelected: (_) {
                  _custom.text = Money.toInput(s);
                  _setAmount(s);
                },
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _custom,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Custom amount',
            prefixText: '${Money.symbol(c.currency)} ',
            helperText:
                'Minimum ${Money.format(c.minAmountMinor, currency: c.currency)}',
          ),
          onChanged: (v) => _setAmount(Money.parseToMinor(v)),
        ),
        const SizedBox(height: Space.md),
        Text(
          c.paysOrganizationDirectly
              ? 'Your donation is paid directly to ${c.organization}\'s PayPal account.'
              : 'Donations are collected by ${AppConstants.merchantName} for ${c.organization}.',
          style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        if (c.updates.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader('Updates from the organisation'),
          for (final u in c.updates) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (u.date != null)
                    Text(
                      DateFormat('d MMM yyyy').format(u.date!),
                      style: t.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(u.title, style: t.titleSmall),
                  const SizedBox(height: Space.xxs),
                  Text(
                    u.body,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ],
    );
  }
}

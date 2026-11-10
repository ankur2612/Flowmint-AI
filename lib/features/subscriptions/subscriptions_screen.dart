import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/gemini_service.dart';
import '../../core/services/receipt_ai.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/document_picker.dart';
import '../../core/widgets/inputs.dart';
import '../../core/widgets/state_views.dart';
import 'subscription_repository.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSubscriptionEditor(context),
        backgroundColor: AppColors.brandDeep,
        foregroundColor: AppColors.onBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: subs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(subscriptionsProvider),
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.autorenew_rounded,
                title: 'Track your recurring costs',
                message:
                    'Add the subscriptions you pay for to see monthly and yearly spend, and get reminded before renewals.',
                actionLabel: 'Add a subscription',
                onAction: () => showSubscriptionEditor(context),
              )
            : _SubscriptionsView(list: list),
      ),
    );
  }
}

class _SubscriptionsView extends ConsumerWidget {
  const _SubscriptionsView({required this.list});

  final List<Subscription> list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final summary = SubscriptionSummary.compute(list, today: DateTime.now());
    final maxCategory = summary.byCategory.isEmpty
        ? 1
        : summary.byCategory.first.value;
    final dayFmt = DateFormat('EEE, d MMM');

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xs,
        Space.gutter,
        96,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONTHLY SPEND',
                style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: Space.xxs),
              Text(Money.format(summary.monthlyMinor), style: t.displaySmall),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      'Per year',
                      Money.format(summary.annualMinor),
                    ),
                  ),
                  Expanded(child: _Metric('Active', '${summary.activeCount}')),
                  Expanded(
                    child: _Metric(
                      'Renewing in 7 days',
                      '${summary.upcoming.length}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (summary.byCategory.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader('By category · per month'),
          AppCard(
            child: Column(
              children: [
                for (final e in summary.byCategory)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(e.key, style: t.bodyMedium)),
                            Text(Money.format(e.value), style: t.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: e.value / maxCategory),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (summary.upcoming.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader('Upcoming renewals'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
            child: Column(
              children: [
                for (final u in summary.upcoming)
                  ListTile(
                    leading: const Icon(
                      Icons.event_repeat_outlined,
                      color: AppColors.warning,
                    ),
                    title: Text(u.subscription.name),
                    subtitle: Text(dayFmt.format(u.date)),
                    trailing: Text(
                      Money.format(
                        u.subscription.amountMinor,
                        currency: u.subscription.currency,
                      ),
                      style: t.titleSmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.xl),
        const SectionHeader('All subscriptions'),
        for (final s in list) ...[
          AppCard(
            onTap: () => showSubscriptionEditor(context, existing: s),
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.sm,
              Space.xs,
              Space.sm,
            ),
            child: Row(
              children: [
                IconTile(
                  Icons.autorenew_rounded,
                  color: s.active ? AppColors.brand : AppColors.textTertiary,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${Money.format(s.amountMinor, currency: s.currency)} / ${s.frequency.unit} · ${s.category}',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: s.active,
                  onChanged: (v) => ref
                      .read(subscriptionRepositoryProvider)
                      .save(
                        Subscription(
                          id: s.id,
                          name: s.name,
                          amountMinor: s.amountMinor,
                          frequency: s.frequency,
                          nextRenewal: s.nextRenewal,
                          currency: s.currency,
                          category: s.category,
                          active: v,
                          reminders: s.reminders,
                        ),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
        ],
        const SizedBox(height: Space.xs),
        Text(
          'Subscriptions are entered by you. FLOWMINT does not read your bank or PayPal account to detect them.',
          style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: t.titleMedium),
        Text(
          label,
          style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

Future<void> showSubscriptionEditor(
  BuildContext context, {
  Subscription? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _SubscriptionEditor(existing: existing),
);

class _SubscriptionEditor extends ConsumerStatefulWidget {
  const _SubscriptionEditor({this.existing});

  final Subscription? existing;

  @override
  ConsumerState<_SubscriptionEditor> createState() =>
      _SubscriptionEditorState();
}

class _SubscriptionEditorState extends ConsumerState<_SubscriptionEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : Money.toInput(widget.existing!.amountMinor),
  );
  late BillingFrequency _frequency =
      widget.existing?.frequency ?? BillingFrequency.monthly;
  late String _category =
      widget.existing?.category ?? subscriptionCategories.first;
  late DateTime _renewal =
      widget.existing?.upcomingRenewal(DateTime.now()) ??
      DateTime.now().add(const Duration(days: 30));
  late bool _reminders = widget.existing?.reminders ?? true;
  bool _saving = false;
  bool _reading = false;

  /// Gemini reads a subscription invoice or bill; the user reviews the
  /// filled form before saving.
  Future<void> _fillFromDocument() async {
    final doc = await pickDocument(context, title: 'Subscription invoice');
    if (doc == null || !mounted) return;
    setState(() => _reading = true);
    try {
      final x = await ref.read(receiptAiProvider).extract(doc);
      if (!mounted) return;
      if (!x.isReceipt || x.totalMinor == null) {
        showMessage(
          context,
          "Couldn't find subscription details. Enter them manually.",
        );
        return;
      }
      setState(() {
        if (x.merchant != null) _name.text = x.merchant!;
        _amount.text = Money.toInput(x.totalMinor!);
        _frequency = switch (x.billingCycle) {
          'weekly' => BillingFrequency.weekly,
          'quarterly' => BillingFrequency.quarterly,
          'yearly' => BillingFrequency.yearly,
          _ => BillingFrequency.monthly,
        };
        if (x.nextBillingDate != null &&
            x.nextBillingDate!.isAfter(DateTime.now())) {
          _renewal = x.nextBillingDate!;
        }
      });
      showMessage(
        context,
        'Filled from your invoice — please check before saving.',
      );
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(subscriptionRepositoryProvider)
          .save(
            Subscription(
              id: widget.existing?.id ?? '',
              name: _name.text.trim(),
              amountMinor: Money.parseToMinor(_amount.text)!,
              frequency: _frequency,
              nextRenewal: _renewal,
              currency:
                  widget.existing?.currency ?? AppConstants.defaultCurrency,
              category: _category,
              active: widget.existing?.active ?? true,
              reminders: _reminders,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    await ref.read(subscriptionRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.lg,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? 'Add subscription'
                    : 'Edit subscription',
                style: t.titleLarge,
              ),
              const SizedBox(height: Space.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _reading ? null : _fillFromDocument,
                  icon: _reading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined, size: 18),
                  label: Text(
                    _reading
                        ? 'Reading with Gemini…'
                        : 'Fill from invoice (photo or PDF)',
                  ),
                ),
              ),
              const SizedBox(height: Space.xs),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Netflix, Spotify, iCloud…',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Space.sm),
              AmountField(
                controller: _amount,
                currency: AppConstants.defaultCurrency,
              ),
              const SizedBox(height: Space.sm),
              DropdownButtonFormField<BillingFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Billing frequency',
                ),
                items: [
                  for (final f in BillingFrequency.values)
                    DropdownMenuItem(value: f, child: Text(f.label)),
                ],
                onChanged: (v) => setState(() => _frequency = v ?? _frequency),
              ),
              const SizedBox(height: Space.sm),
              DropdownButtonFormField<String>(
                initialValue: subscriptionCategories.contains(_category)
                    ? _category
                    : 'Other',
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in subscriptionCategories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Next renewal'),
                trailing: Text(
                  DateFormat('d MMM yyyy').format(_renewal),
                  style: t.titleSmall,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _renewal,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => _renewal = picked);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Renewal reminder'),
                subtitle: const Text('Push notification 3 days before renewal'),
                value: _reminders,
                onChanged: (v) => setState(() => _reminders = v),
              ),
              const SizedBox(height: Space.md),
              LoadingButton(label: 'Save', loading: _saving, onPressed: _save),
              if (widget.existing != null)
                TextButton(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('Delete subscription'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

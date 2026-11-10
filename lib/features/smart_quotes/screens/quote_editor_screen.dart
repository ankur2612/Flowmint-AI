import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/state_views.dart';
import '../../assistant/assistant_repository.dart';
import '../quote_ai.dart';
import '../quote_models.dart';
import '../quote_repository.dart';

class QuoteEditorScreen extends ConsumerStatefulWidget {
  const QuoteEditorScreen({super.key, this.seed, this.existingId});

  final QuoteSeed? seed;
  final String? existingId;

  @override
  ConsumerState<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _ItemRow {
  _ItemRow([QuoteLineItem? item])
    : description = TextEditingController(text: item?.description ?? ''),
      quantity = TextEditingController(text: _qty(item?.quantity ?? 1)),
      price = TextEditingController(
        text: item == null || item.unitPriceMinor == 0
            ? ''
            : Money.toInput(item.unitPriceMinor),
      );

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController price;

  QuoteLineItem toItem() => QuoteLineItem(
    description: description.text.trim(),
    quantity: double.tryParse(quantity.text.trim()) ?? 0,
    unitPriceMinor: Money.parseToMinor(price.text) ?? 0,
  );

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _MilestoneRow {
  _MilestoneRow([QuoteMilestone? m])
    : title = TextEditingController(text: m?.title ?? ''),
      percent = TextEditingController(text: m == null ? '' : '${m.percent}'),
      status = m?.status ?? MilestoneStatus.unpaid;

  final TextEditingController title;
  final TextEditingController percent;
  final MilestoneStatus status;

  QuoteMilestone toMilestone() => QuoteMilestone(
    title: title.text.trim(),
    percent: int.tryParse(percent.text.trim()) ?? 0,
    status: status,
  );

  void dispose() {
    title.dispose();
    percent.dispose();
  }
}

class _QuoteEditorScreenState extends ConsumerState<QuoteEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _tax = TextEditingController(text: '18');
  final _discount = TextEditingController();
  final _notes = TextEditingController();
  final _items = <_ItemRow>[];
  final _milestones = <_MilestoneRow>[];
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  Quotation? _existing;
  bool _aiSuggested = false;
  bool _loading = false;
  bool _drafting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingId != null) {
      _loading = true;
      _loadExisting(widget.existingId!);
    } else {
      _applySeed(widget.seed);
    }
  }

  Future<void> _loadExisting(String id) async {
    try {
      final q = await ref.read(quoteRepositoryProvider).fetch(id);
      if (!mounted) return;
      if (q == null) {
        showMessage(context, 'Quotation not found.');
        context.pop();
        return;
      }
      _existing = q;
      _client.text = q.clientName;
      _company.text = q.clientCompany ?? '';
      _email.text = q.clientEmail ?? '';
      _title.text = q.projectTitle;
      _description.text = q.projectDescription;
      _tax.text = q.taxRatePercent == 0 ? '' : _ItemRow._qty(q.taxRatePercent);
      _discount.text = q.discountMinor == 0
          ? ''
          : Money.toInput(q.discountMinor);
      _notes.text = q.notes;
      _validUntil = q.validUntil ?? _validUntil;
      _aiSuggested = q.aiSuggested;
      _replaceRows(q.items, q.milestones);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySeed(QuoteSeed? seed) {
    if (seed?.clientName != null) _client.text = seed!.clientName!;
    if (seed?.projectTitle != null) _title.text = seed!.projectTitle!;
    if (seed?.projectDescription != null) {
      _description.text = seed!.projectDescription!;
    }
    if (seed?.notes != null) _notes.text = seed!.notes!;
    _aiSuggested = seed?.aiSuggested ?? false;
    _replaceRows(
      seed?.items ?? const [],
      seed == null || seed.milestones.isEmpty
          ? const [
              QuoteMilestone(title: 'Advance', percent: 50),
              QuoteMilestone(title: 'On delivery', percent: 50),
            ]
          : seed.milestones,
    );
  }

  void _replaceRows(
    List<QuoteLineItem> items,
    List<QuoteMilestone> milestones,
  ) {
    for (final r in _items) {
      r.dispose();
    }
    for (final r in _milestones) {
      r.dispose();
    }
    _items
      ..clear()
      ..addAll(items.isEmpty ? [_ItemRow()] : items.map(_ItemRow.new));
    _milestones
      ..clear()
      ..addAll(milestones.map(_MilestoneRow.new));
  }

  @override
  void dispose() {
    for (final c in [
      _client,
      _company,
      _email,
      _title,
      _description,
      _tax,
      _discount,
      _notes,
    ]) {
      c.dispose();
    }
    for (final r in _items) {
      r.dispose();
    }
    for (final r in _milestones) {
      r.dispose();
    }
    super.dispose();
  }

  QuoteTotals get _totals => QuoteCalculator.totals(
    _items.map((r) => r.toItem()).toList(),
    taxRatePercent: double.tryParse(_tax.text.trim()) ?? 0,
    discountMinor: Money.parseToMinor(_discount.text) ?? 0,
  );

  Future<void> _draftWithAi() async {
    final controller = TextEditingController(text: _description.text);
    final description = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          MediaQuery.viewInsetsOf(c).bottom + Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Describe the project',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Gemini drafts line items and milestones. You can edit everything before saving.',
              style: Theme.of(
                c,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText:
                    'A 5-page marketing website with blog, contact form and SEO setup. Budget around ₹80,000.',
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Draft quotation'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (description == null || description.isEmpty) return;

    setState(() => _drafting = true);
    try {
      final seed = await ref
          .read(quoteAiProvider)
          .draft(
            description,
            clientName: _client.text.trim().isEmpty
                ? null
                : _client.text.trim(),
          );
      if (!mounted) return;
      setState(() => _applySeed(seed));
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  static const _stepTitles = [
    'Client',
    'Project',
    'Items',
    'Pricing',
    'Milestones',
  ];
  int _step = 0;

  /// Validates the visible step, then advances or saves on the last step.
  void _next() {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_step == 2 && _items.isEmpty) {
      showMessage(context, 'Add at least one line item.');
      return;
    }
    if (_step < _stepTitles.length - 1) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    // Earlier steps are not mounted, so re-check their required fields.
    final firstInvalid = _client.text.trim().isEmpty
        ? 0
        : _title.text.trim().isEmpty
        ? 1
        : _items.any((r) {
            final i = r.toItem();
            return i.description.isEmpty ||
                i.quantity <= 0 ||
                Money.parseToMinor(r.price.text) == null;
          })
        ? 2
        : null;
    if (firstInvalid != null) {
      setState(() => _step = firstInvalid);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _form.currentState?.validate(),
      );
      return;
    }
    final items = _items.map((r) => r.toItem()).toList();
    if (items.isEmpty) {
      showMessage(context, 'Add at least one line item.');
      return;
    }
    final milestones = _milestones.map((r) => r.toMilestone()).toList();
    if (milestones.isNotEmpty &&
        milestones.fold<int>(0, (s, m) => s + m.percent) != 100) {
      showMessage(context, 'Milestone percentages must add up to 100%.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(quoteRepositoryProvider);
    try {
      final existing = _existing;
      final id = await repo.save(
        Quotation(
          id: existing?.id ?? '',
          number: existing?.number ?? repo.newNumber(),
          clientName: _client.text.trim(),
          clientCompany: _company.text.trim().isEmpty
              ? null
              : _company.text.trim(),
          clientEmail: _email.text.trim().isEmpty ? null : _email.text.trim(),
          projectTitle: _title.text.trim(),
          projectDescription: _description.text.trim(),
          currency: existing?.currency ?? AppConstants.defaultCurrency,
          items: items,
          taxRatePercent: double.tryParse(_tax.text.trim()) ?? 0,
          discountMinor: Money.parseToMinor(_discount.text) ?? 0,
          milestones: milestones,
          validUntil: _validUntil,
          notes: _notes.text.trim(),
          status: existing?.status ?? QuoteStatus.draft,
          aiSuggested: _aiSuggested,
          createdAt: existing?.createdAt ?? DateTime.now(),
        ),
      );
      final source = widget.seed?.sourceMessageId;
      if (source != null) {
        await ref
            .read(assistantRepositoryProvider)
            .markActionCompleted(source, '/quotes/$id');
      }
      if (!mounted) return;
      if (existing != null) {
        context.pop();
      } else {
        context.pushReplacement('/quotes/$id');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    final totals = _totals;
    final currency = _existing?.currency ?? AppConstants.defaultCurrency;
    String money(int v) => Money.format(v, currency: currency);
    final percentSum = _milestones.fold<int>(
      0,
      (s, r) => s + (int.tryParse(r.percent.text) ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New quotation' : 'Edit quotation'),
        actions: [
          TextButton.icon(
            onPressed: _drafting ? null : _draftWithAi,
            icon: _drafting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Draft with AI'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            120,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_aiSuggested)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: AppCard(
                  color: AppColors.brandSubtle,
                  borderColor: AppColors.brandMuted,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          'Drafted by Gemini. Prices are suggestions — review every line before sending.',
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _StepHeader(step: _step, titles: _stepTitles),
            const SizedBox(height: Space.lg),
            if (_step == 0) ...[
              const SectionHeader('Client'),
              TextFormField(
                controller: _client,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Client name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _company,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Company (optional)',
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_step == 1) ...[
              const SectionHeader('Project'),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Project title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Scope / description',
                ),
              ),
            ],
            if (_step == 2) ...[
              SectionHeader(
                'Line items',
                actionLabel: 'Add item',
                onAction: () => setState(() => _items.add(_ItemRow())),
              ),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _LineItemCard(
                    key: ObjectKey(_items[i]),
                    row: _items[i],
                    currency: currency,
                    onRemove: _items.length == 1
                        ? null
                        : () => setState(
                            () => disposeLater(_items.removeAt(i).dispose),
                          ),
                  ),
                ),
            ],
            if (_step == 3) ...[
              const SectionHeader('Pricing'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tax,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Tax rate',
                        suffixText: '%',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final r = double.tryParse(v.trim());
                        return r == null || r < 0 || r > 100 ? '0–100' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _discount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Discount',
                        prefixText: '${Money.symbol(currency)} ',
                      ),
                      validator: (v) =>
                          v == null ||
                              v.trim().isEmpty ||
                              Money.parseToMinor(v) != null
                          ? null
                          : 'Invalid',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              AppCard(
                child: Column(
                  children: [
                    DetailRow('Subtotal', money(totals.subtotalMinor)),
                    if (totals.discountMinor > 0)
                      DetailRow('Discount', '− ${money(totals.discountMinor)}'),
                    DetailRow('Tax', money(totals.taxMinor)),
                    const Divider(height: Space.md),
                    DetailRow(
                      'Total',
                      money(totals.totalMinor),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ],
            if (_step == 4) ...[
              SectionHeader(
                'Payment milestones',
                actionLabel: 'Add',
                onAction: () =>
                    setState(() => _milestones.add(_MilestoneRow())),
              ),
              for (var i = 0; i < _milestones.length; i++)
                Padding(
                  key: ObjectKey(_milestones[i]),
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _milestones[i].title,
                          decoration: const InputDecoration(
                            labelText: 'Milestone',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      SizedBox(
                        width: 86,
                        child: TextFormField(
                          controller: _milestones[i].percent,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(suffixText: '%'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove milestone',
                        onPressed: () => setState(
                          () => disposeLater(_milestones.removeAt(i).dispose),
                        ),
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_milestones.isNotEmpty)
                Text(
                  percentSum == 100
                      ? 'Milestones cover the full amount.'
                      : 'Milestones total $percentSum% — they must add up to 100%.',
                  style: t.bodySmall?.copyWith(
                    color: percentSum == 100
                        ? AppColors.brand
                        : AppColors.warning,
                  ),
                ),
              const SizedBox(height: Space.xl),
              const SectionHeader('Terms'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Valid until'),
                trailing: Text(
                  DateFormat('d MMM yyyy').format(_validUntil),
                  style: t.titleSmall,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _validUntil,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _validUntil = picked);
                },
              ),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes, assumptions, exclusions',
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            Space.md,
          ),
          child: Row(
            children: [
              if (_step > 0) ...[
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: Space.sm),
              ],
              Expanded(
                flex: 3,
                child: LoadingButton(
                  label: _step < _stepTitles.length - 1
                      ? 'Next · ${_stepTitles[_step + 1]}'
                      : (_existing == null
                            ? 'Save and preview'
                            : 'Save changes'),
                  loading: _saving,
                  onPressed: _drafting ? null : _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineItemCard extends StatelessWidget {
  const _LineItemCard({
    super.key,
    required this.row,
    required this.currency,
    required this.onRemove,
  });

  final _ItemRow row;
  final String currency;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final item = row.toItem();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.sm,
        Space.xs,
        Space.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.description,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextFormField(
                  controller: row.quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Qty',
                    isDense: true,
                  ),
                  validator: (v) {
                    final q = double.tryParse(v?.trim() ?? '');
                    return q == null || q <= 0 ? 'Invalid' : null;
                  },
                ),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: TextFormField(
                  controller: row.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Unit price',
                    isDense: true,
                    prefixText: '${Money.symbol(currency)} ',
                  ),
                  validator: (v) =>
                      Money.parseToMinor(v ?? '') == null ? 'Invalid' : null,
                ),
              ),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: 96,
                child: Text(
                  Money.format(item.amountMinor, currency: currency),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: Space.xs),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP ${step + 1} OF ${titles.length}',
          style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            for (var i = 0; i < titles.length; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  margin: EdgeInsets.only(
                    right: i == titles.length - 1 ? 0 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: i <= step
                        ? AppColors.brand
                        : AppColors.surfaceHighest,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

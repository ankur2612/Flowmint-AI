import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/receipt_ai.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/document_picker.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/state_views.dart';
import '../../assistant/assistant_repository.dart';
import '../split_models.dart';
import '../split_repository.dart';

class SplitEditorScreen extends ConsumerStatefulWidget {
  const SplitEditorScreen({super.key, this.draft});

  final SplitDraft? draft;

  @override
  ConsumerState<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _PersonRow {
  _PersonRow(String name, {this.isOrganizer = false, int? customMinor})
    : id = const Uuid().v4(),
      name = TextEditingController(text: name),
      custom = TextEditingController(
        text: customMinor == null ? '' : Money.toInput(customMinor),
      );

  final String id;
  final bool isOrganizer;
  final TextEditingController name;
  final TextEditingController custom;

  void dispose() {
    name.dispose();
    custom.dispose();
  }
}

class _SplitEditorScreenState extends ConsumerState<SplitEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _total = TextEditingController();
  final _subtotal = TextEditingController();
  final _tax = TextEditingController();
  final _tip = TextEditingController();
  final _discount = TextEditingController();
  bool _itemised = false;
  final _people = <_PersonRow>[];
  final _currency = AppConstants.defaultCurrency;
  SplitMode _mode = SplitMode.equal;
  AiDocument? _bill;
  ReceiptExtraction? _extraction;
  bool _scanning = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _title.text = d?.title ?? '';
    if (d?.totalMinor != null) _total.text = Money.toInput(d!.totalMinor!);

    final names = [...?d?.participantNames]
      ..removeWhere((n) => n.toLowerCase() == 'you' || n.toLowerCase() == 'me');
    _people.add(_PersonRow('You', isOrganizer: true));
    for (final n in names) {
      _people.add(_PersonRow(n));
    }
    final count = d?.participantCount ?? (names.isEmpty ? 2 : names.length + 1);
    while (_people.length < count.clamp(2, 50)) {
      _people.add(_PersonRow('Person ${_people.length + 1}'));
    }

    if (d?.billDocument != null) {
      _bill = d!.billDocument;
      if (d.totalMinor == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scan(_bill!));
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _total.dispose();
    for (final c in [_subtotal, _tax, _tip, _discount]) {
      c.dispose();
    }
    for (final p in _people) {
      p.dispose();
    }
    super.dispose();
  }

  int? get _totalMinor => Money.parseToMinor(_total.text);

  int _minor(TextEditingController c) => Money.parseToMinor(c.text) ?? 0;

  BillBreakdown? get _breakdown => _itemised && _minor(_subtotal) > 0
      ? BillBreakdown(
          subtotalMinor: _minor(_subtotal),
          taxMinor: _minor(_tax),
          tipMinor: _minor(_tip),
          discountMinor: _minor(_discount),
        )
      : null;

  /// Keeps the total in sync with the itemised breakdown.
  void _recomputeTotal() {
    final b = _breakdown;
    setState(() {
      if (b != null) _total.text = Money.toInput(b.totalMinor);
    });
  }

  List<int> get _shares {
    final total = _totalMinor ?? 0;
    if (_mode == SplitMode.equal) {
      return SplitCalculator.equalShares(total, _people.length);
    }
    return [for (final p in _people) Money.parseToMinor(p.custom.text) ?? 0];
  }

  Future<void> _attachBill() async {
    final image = await pickDocument(context);
    if (image == null) return;
    setState(() => _bill = image);
    await _scan(image);
  }

  Future<void> _scan(AiDocument image) async {
    setState(() {
      _scanning = true;
      _extraction = null;
    });
    try {
      final result = await ref.read(receiptAiProvider).extract(image);
      if (!mounted) return;
      if (!result.isReceipt || result.totalMinor == null) {
        showMessage(
          context,
          "Couldn't find a total on that image. Enter the amount manually.",
        );
      }
      setState(() => _extraction = result.isReceipt ? result : null);
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyExtraction() {
    final x = _extraction;
    if (x == null) return;
    setState(() {
      if (x.totalMinor != null) _total.text = Money.toInput(x.totalMinor!);
      final hasBreakdown =
          x.subtotalMinor != null &&
          (x.taxMinor != null || x.tipMinor != null || x.discountMinor != null);
      if (hasBreakdown) {
        _itemised = true;
        _subtotal.text = Money.toInput(x.subtotalMinor!);
        _tax.text = x.taxMinor == null ? '' : Money.toInput(x.taxMinor!);
        _tip.text = x.tipMinor == null ? '' : Money.toInput(x.tipMinor!);
        _discount.text = x.discountMinor == null
            ? ''
            : Money.toInput(x.discountMinor!);
      }
      if (_title.text.trim().isEmpty && x.merchant != null) {
        _title.text = x.merchant!;
      }
      _extraction = null;
    });
  }

  void _addPerson() {
    if (_people.length >= 50) return;
    setState(() => _people.add(_PersonRow('')));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final total = _totalMinor!;
    final shares = _shares;
    if (_people.length < 2) {
      showMessage(context, 'Add at least two people to split with.');
      return;
    }
    if (_mode == SplitMode.custom &&
        SplitCalculator.unallocated(total, shares) != 0) {
      showMessage(context, 'Custom shares must add up to the total.');
      return;
    }
    setState(() => _saving = true);
    try {
      final group = ExpenseGroup(
        id: '',
        title: _title.text.trim(),
        totalMinor: total,
        currency: _currency,
        mode: _mode,
        merchant: _title.text.trim(),
        breakdown: _breakdown,
        createdAt: DateTime.now(),
        participants: [
          for (var i = 0; i < _people.length; i++)
            SplitParticipant(
              id: _people[i].id,
              name: _people[i].name.text.trim(),
              shareMinor: shares[i],
              isOrganizer: _people[i].isOrganizer,
              settled: _people[i].isOrganizer,
            ),
        ],
      );
      final id = await ref.read(splitRepositoryProvider).create(group);
      final source = widget.draft?.sourceMessageId;
      if (source != null) {
        await ref
            .read(assistantRepositoryProvider)
            .markActionCompleted(source, '/split/$id');
      }
      if (mounted) context.pushReplacement('/split/$id');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shares = _shares;
    final total = _totalMinor ?? 0;
    final remaining = SplitCalculator.unallocated(total, shares);

    return Scaffold(
      appBar: AppBar(title: const Text('New split')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            120,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'Dinner at Olive Bistro',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Add a short description'
                  : null,
            ),
            const SizedBox(height: Space.md),
            AmountField(
              controller: _total,
              currency: _currency,
              label: _itemised ? 'Total bill (calculated)' : 'Total bill',
              onChanged: (_) => setState(() {}),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: Alignment.topCenter,
              child: !_itemised
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _itemised = true),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Itemise tax, tip & discount'),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _MiniAmount(
                                  'Subtotal',
                                  _subtotal,
                                  _currency,
                                  _recomputeTotal,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: _MiniAmount(
                                  'Tax / GST',
                                  _tax,
                                  _currency,
                                  _recomputeTotal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.sm),
                          Row(
                            children: [
                              Expanded(
                                child: _MiniAmount(
                                  'Tip / service',
                                  _tip,
                                  _currency,
                                  _recomputeTotal,
                                ),
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: _MiniAmount(
                                  'Discount',
                                  _discount,
                                  _currency,
                                  _recomputeTotal,
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _itemised = false),
                              child: const Text('Remove breakdown'),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: Space.sm),
            _BillAttachment(
              hasBill: _bill != null,
              scanning: _scanning,
              extraction: _extraction,
              onAttach: _attachBill,
              onApply: _applyExtraction,
              onDismiss: () => setState(() => _extraction = null),
            ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(child: Text('Split between', style: t.titleMedium)),
                SegmentedButton<SplitMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: SplitMode.equal, label: Text('Equal')),
                    ButtonSegment(
                      value: SplitMode.custom,
                      label: Text('Custom'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() {
                    _mode = s.first;
                    if (_mode == SplitMode.custom) {
                      final eq = SplitCalculator.equalShares(
                        total,
                        _people.length,
                      );
                      for (var i = 0; i < _people.length; i++) {
                        _people[i].custom.text = Money.toInput(eq[i]);
                      }
                    }
                  }),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: [
                  for (var i = 0; i < _people.length; i++)
                    _PersonTile(
                      key: ValueKey(_people[i].id),
                      row: _people[i],
                      mode: _mode,
                      shareMinor: shares[i],
                      currency: _currency,
                      onChanged: () => setState(() {}),
                      onRemove: _people[i].isOrganizer || _people.length <= 2
                          ? null
                          : () => setState(
                              () => disposeLater(_people.removeAt(i).dispose),
                            ),
                    ),
                  TextButton.icon(
                    onPressed: _addPerson,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
                    label: const Text('Add person'),
                  ),
                ],
              ),
            ),
            if (_mode == SplitMode.custom && total > 0) ...[
              const SizedBox(height: Space.sm),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  key: ValueKey(remaining),
                  remaining == 0
                      ? 'Shares balance the total.'
                      : remaining > 0
                      ? '${Money.format(remaining, currency: _currency)} still to allocate'
                      : '${Money.format(-remaining, currency: _currency)} over the total',
                  style: t.bodySmall?.copyWith(
                    color: remaining == 0 ? AppColors.brand : AppColors.warning,
                  ),
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
          child: LoadingButton(
            label: 'Create split',
            loading: _saving,
            onPressed: _scanning ? null : _save,
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    super.key,
    required this.row,
    required this.mode,
    required this.shareMinor,
    required this.currency,
    required this.onChanged,
    required this.onRemove,
  });

  final _PersonRow row;
  final SplitMode mode;
  final int shareMinor;
  final String currency;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: row.isOrganizer
                ? AppColors.brandSubtle
                : AppColors.surfaceHighest,
            child: Icon(
              row.isOrganizer
                  ? Icons.star_rounded
                  : Icons.person_outline_rounded,
              size: 16,
              color: row.isOrganizer
                  ? AppColors.brand
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: TextFormField(
              controller: row.name,
              readOnly: row.isOrganizer,
              textCapitalization: TextCapitalization.words,
              style: t.bodyLarge,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Name',
                helperText: row.isOrganizer ? 'Paid the bill' : null,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
          ),
          if (mode == SplitMode.equal)
            Text(
              Money.format(shareMinor, currency: currency),
              style: t.titleSmall,
            )
          else
            SizedBox(
              width: 104,
              child: TextFormField(
                controller: row.custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.end,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: Money.symbol(currency),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                validator: (v) =>
                    Money.parseToMinor(v ?? '') == null ? 'Invalid' : null,
              ),
            ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              size: 20,
              color: onRemove == null
                  ? Colors.transparent
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillAttachment extends StatelessWidget {
  const _BillAttachment({
    required this.hasBill,
    required this.scanning,
    required this.extraction,
    required this.onAttach,
    required this.onApply,
    required this.onDismiss,
  });

  final bool hasBill;
  final bool scanning;
  final ReceiptExtraction? extraction;
  final VoidCallback onAttach;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final x = extraction;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: scanning
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.md),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: Space.sm),
                  Text('Reading your bill with Gemini…'),
                ],
              ),
            )
          : x != null && x.totalMinor != null
          ? AppCard(
              color: AppColors.brandSubtle,
              borderColor: AppColors.brandMuted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: Space.xs),
                      Text(
                        'Read from your bill — please check',
                        style: t.labelMedium?.copyWith(color: AppColors.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  if (x.merchant != null) DetailRow('Merchant', x.merchant!),
                  DetailRow(
                    'Total',
                    Money.format(x.totalMinor!, currency: x.currency),
                    emphasize: true,
                  ),
                  if (x.currency != AppConstants.defaultCurrency)
                    Text(
                      'This bill is in ${x.currency}. Splits are recorded in '
                      '${AppConstants.defaultCurrency}; confirm the amount before using it.',
                      style: t.bodySmall?.copyWith(color: AppColors.warning),
                    ),
                  const SizedBox(height: Space.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('Ignore'),
                      ),
                      const SizedBox(width: Space.xs),
                      FilledButton(
                        onPressed: onApply,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        child: const Text('Use these values'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAttach,
                icon: Icon(
                  hasBill
                      ? Icons.check_circle_outline
                      : Icons.document_scanner_outlined,
                  size: 19,
                ),
                label: Text(
                  hasBill ? 'Bill attached · scan again' : 'Scan a bill',
                ),
              ),
            ),
    );
  }
}

class _MiniAmount extends StatelessWidget {
  const _MiniAmount(this.label, this.controller, this.currency, this.onChanged);

  final String label;
  final TextEditingController controller;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixText: '${Money.symbol(currency)} ',
      ),
      validator: (v) =>
          v == null || v.trim().isEmpty || Money.parseToMinor(v) != null
          ? null
          : 'Invalid',
    );
  }
}

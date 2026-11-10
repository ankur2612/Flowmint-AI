import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/payments/payment_models.dart';
import '../../../core/payments/payment_status_screen.dart';
import '../../../core/payments/paypal_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/receipt_ai.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/document_picker.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/state_views.dart';
import '../../assistant/assistant_repository.dart';
import '../refund_models.dart';
import '../refund_repository.dart';
import 'refunds_screen.dart';

class RefundEditorScreen extends ConsumerStatefulWidget {
  const RefundEditorScreen({
    super.key,
    this.draft,
    this.linkedOrderId,
    this.existingId,
  });

  final RefundDraft? draft;
  final String? linkedOrderId;
  final String? existingId;

  @override
  ConsumerState<RefundEditorScreen> createState() => _RefundEditorScreenState();
}

class _RefundEditorScreenState extends ConsumerState<RefundEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _merchant = TextEditingController();
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _policy = TextEditingController();
  String _currency = AppConstants.defaultCurrency;
  DateTime? _purchaseDate;
  RefundRequest? _existing;
  RefundAnalysis? _analysis;
  RefundStatus _status = RefundStatus.draft;
  String? _linkedOrderId;
  AiDocument? _receipt;
  ReceiptExtraction? _extraction;
  bool _loading = false;
  bool _scanning = false;
  bool _analysing = false;
  bool _saving = false;
  bool _refunding = false;

  @override
  void initState() {
    super.initState();
    _linkedOrderId = widget.linkedOrderId;
    final d = widget.draft;
    if (d != null) {
      _merchant.text = d.merchant ?? '';
      _reference.text = d.orderReference ?? '';
      if (d.amountMinor != null) _amount.text = Money.toInput(d.amountMinor!);
      _reason.text = d.reason ?? '';
      if (d.receiptDocument != null) {
        _receipt = d.receiptDocument;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scan(d.receiptDocument!),
        );
      }
    }
    if (widget.existingId != null) {
      _loading = true;
      _load(widget.existingId!);
    }
  }

  Future<void> _load(String id) async {
    try {
      final r = await ref.read(refundRepositoryProvider).fetch(id);
      if (!mounted) return;
      if (r == null) {
        showMessage(context, 'Refund request not found.');
        context.pop();
        return;
      }
      _existing = r;
      _merchant.text = r.merchant;
      _reference.text = r.orderReference ?? '';
      if (r.amountMinor != null) _amount.text = Money.toInput(r.amountMinor!);
      _reason.text = r.reason;
      _policy.text = r.policyText ?? '';
      _currency = r.currency;
      _purchaseDate = r.purchaseDate;
      _analysis = r.analysis;
      _status = r.status;
      _linkedOrderId = r.linkedOrderId;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_merchant, _reference, _amount, _reason, _policy]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _attach() async {
    final image = await pickDocument(context);
    if (image == null) return;
    setState(() => _receipt = image);
    await _scan(image);
  }

  Future<void> _scan(AiDocument image) async {
    setState(() => _scanning = true);
    try {
      final x = await ref.read(receiptAiProvider).extract(image);
      if (!mounted) return;
      if (!x.isReceipt) {
        showMessage(
          context,
          "That doesn't look like a receipt. Enter the details manually.",
        );
      }
      setState(() => _extraction = x.isReceipt ? x : null);
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyExtraction() {
    final x = _extraction!;
    setState(() {
      if (x.merchant != null) _merchant.text = x.merchant!;
      if (x.orderReference != null) _reference.text = x.orderReference!;
      if (x.totalMinor != null) _amount.text = Money.toInput(x.totalMinor!);
      _currency = x.currency;
      _purchaseDate = x.purchaseDate ?? _purchaseDate;
      _extraction = null;
    });
  }

  RefundRequest _current() => RefundRequest(
    id: _existing?.id ?? '',
    merchant: _merchant.text.trim(),
    reason: _reason.text.trim(),
    createdAt: _existing?.createdAt ?? DateTime.now(),
    orderReference: _reference.text.trim().isEmpty
        ? null
        : _reference.text.trim(),
    purchaseDate: _purchaseDate,
    amountMinor: Money.parseToMinor(_amount.text),
    currency: _currency,
    policyText: _policy.text.trim().isEmpty ? null : _policy.text.trim(),
    analysis: _analysis,
    status: _status,
    linkedOrderId: _linkedOrderId,
  );

  Future<void> _analyse() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _analysing = true);
    try {
      final a = await ref.read(refundRepositoryProvider).analyse(_current());
      if (mounted) setState(() => _analysis = a);
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  Future<void> _save({bool pop = true}) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(refundRepositoryProvider).save(_current());
      final source = widget.draft?.sourceMessageId;
      if (source != null) {
        await ref
            .read(assistantRepositoryProvider)
            .markActionCompleted(source, '/refunds/$id');
      }
      if (!mounted) return;
      if (pop) {
        context.pop();
      } else {
        context.pushReplacement('/refunds/$id');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refundViaPayPal(PaymentRecord order) async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Request a PayPal refund?'),
        content: Text(
          'FLOWMINT will ask PayPal to refund ${Money.format(order.amountMinor, currency: order.currency)} '
          'to the PayPal account that paid for this order. Eligibility is checked by our backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Request refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _refunding = true);
    try {
      final status = await ref
          .read(paypalServiceProvider)
          .refundOrder(order.id, reason: _reason.text.trim());
      _merchant.text = AppConstants.merchantName;
      _reference.text = order.paypalOrderId ?? order.id;
      _amount.text = Money.toInput(order.amountMinor);
      _currency = order.currency;
      _status = status == 'COMPLETED'
          ? RefundStatus.refunded
          : RefundStatus.processing;
      await ref.read(refundRepositoryProvider).save(_current());
      if (mounted) {
        showMessage(
          context,
          status == 'COMPLETED'
              ? 'PayPal confirmed the refund.'
              : 'PayPal is processing the refund. Status updates automatically.',
        );
      }
    } on PaymentException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingView());
    final linked = _linkedOrderId;
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Refund request' : _existing!.merchant),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(refundRepositoryProvider).delete(_existing!.id);
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
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
          children: linked != null ? _linkedOrderBody(linked) : _manualBody(),
        ),
      ),
      bottomNavigationBar: linked != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xs,
                  Space.gutter,
                  Space.md,
                ),
                child: LoadingButton(
                  label: _existing == null ? 'Save request' : 'Save changes',
                  loading: _saving,
                  onPressed: _scanning || _analysing
                      ? null
                      : () => _save(pop: _existing != null),
                ),
              ),
            ),
    );
  }

  List<Widget> _linkedOrderBody(String orderId) {
    final t = Theme.of(context).textTheme;
    final order = ref.watch(
      paymentRecordProvider((PaymentKind.shopping, orderId)),
    );
    return [
      order.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Space.xxl),
          child: LoadingView(),
        ),
        error: (e, _) => ErrorState(message: friendlyError(e)),
        data: (o) {
          if (o == null) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Order not found',
              message: 'This order is not available.',
            );
          }
          final refundRequested = o.refundStatus != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  children: [
                    DetailRow('Order', o.description),
                    DetailRow(
                      'Paid',
                      Money.format(o.amountMinor, currency: o.currency),
                      emphasize: true,
                    ),
                    if (o.completedAt != null)
                      DetailRow(
                        'Date',
                        DateFormat('d MMM yyyy').format(o.completedAt!),
                      ),
                    DetailRow('Payment status', o.status.label),
                    if (o.refundStatus != null)
                      DetailRow('Refund status', o.refundStatus!),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              Text(
                'This order was paid through FLOWMINT with PayPal, so a refund can be requested directly. '
                'Eligibility (refund window, prior refunds) is checked by the FLOWMINT backend and the result comes from PayPal.',
                style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Space.lg),
              if (refundRequested)
                Center(
                  child: StatusBadge(
                    o.status == PaymentStatus.refunded
                        ? 'Refunded by PayPal'
                        : 'Refund ${o.refundStatus!.toLowerCase()}',
                    tone: paymentTone(o.status),
                  ),
                )
              else ...[
                TextFormField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason for refund',
                  ),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Describe the reason'
                      : null,
                ),
                const SizedBox(height: Space.lg),
                LoadingButton(
                  label: 'Request refund through PayPal',
                  icon: Icons.undo_rounded,
                  loading: _refunding,
                  onPressed: o.status == PaymentStatus.completed
                      ? () => _refundViaPayPal(o)
                      : null,
                ),
              ],
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _manualBody() {
    final t = Theme.of(context).textTheme;
    final x = _extraction;
    return [
      AppCard(
        onTap: _scanning ? null : _attach,
        child: Row(
          children: [
            IconTile(
              _receipt != null
                  ? Icons.check_rounded
                  : Icons.document_scanner_outlined,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                _scanning
                    ? 'Reading receipt with Gemini…'
                    : (_receipt != null)
                    ? 'Receipt attached · tap to replace'
                    : 'Scan or upload your receipt',
                style: t.titleSmall,
              ),
            ),
            if (_scanning)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      if (x != null) ...[
        const SizedBox(height: Space.sm),
        AppCard(
          color: AppColors.brandSubtle,
          borderColor: AppColors.brandMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Read from your receipt — please check',
                style: t.labelMedium?.copyWith(color: AppColors.brand),
              ),
              if (x.merchant != null) DetailRow('Merchant', x.merchant!),
              if (x.orderReference != null)
                DetailRow('Reference', x.orderReference!),
              if (x.purchaseDate != null)
                DetailRow(
                  'Date',
                  DateFormat('d MMM yyyy').format(x.purchaseDate!),
                ),
              if (x.totalMinor != null)
                DetailRow(
                  'Total',
                  Money.format(x.totalMinor!, currency: x.currency),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _applyExtraction,
                  child: const Text('Use these values'),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Space.lg),
      TextFormField(
        controller: _merchant,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Merchant'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: Space.sm),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Order / invoice no.',
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${Money.symbol(_currency)} ',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty || Money.parseToMinor(v) != null
                  ? null
                  : 'Invalid',
            ),
          ),
        ],
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event_outlined),
        title: const Text('Purchase date'),
        trailing: Text(
          _purchaseDate == null
              ? 'Not set'
              : DateFormat('d MMM yyyy').format(_purchaseDate!),
          style: t.titleSmall,
        ),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _purchaseDate ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 730)),
            lastDate: DateTime.now(),
          );
          if (picked != null) setState(() => _purchaseDate = picked);
        },
      ),
      TextFormField(
        controller: _reason,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'What went wrong?'),
        validator: (v) =>
            (v == null || v.trim().length < 5) ? 'Describe the issue' : null,
      ),
      const SizedBox(height: Space.sm),
      TextFormField(
        controller: _policy,
        minLines: 2,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: 'Merchant refund policy (optional)',
          hintText:
              "Paste the merchant's return or refund policy for a more accurate assessment",
        ),
      ),
      const SizedBox(height: Space.md),
      OutlinedButton.icon(
        onPressed: _analysing ? null : _analyse,
        icon: _analysing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(
          _analysis == null ? 'Analyse with Gemini' : 'Analyse again',
        ),
      ),
      if (_analysis != null) ...[
        const SizedBox(height: Space.lg),
        _AnalysisCard(analysis: _analysis!),
      ],
      if (_existing != null) ...[
        const SizedBox(height: Space.xl),
        DropdownButtonFormField<RefundStatus>(
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'Status (reported by you)',
          ),
          items: [
            for (final s in RefundStatus.values)
              DropdownMenuItem(
                value: s,
                child: Row(
                  children: [StatusBadge(s.label, tone: refundTone(s))],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _status = v ?? _status),
        ),
      ],
    ];
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.analysis});

  final RefundAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = analysis;
    final tone = switch (a.eligibility) {
      Eligibility.likely => Tone.positive,
      Eligibility.unclear => Tone.warning,
      Eligibility.unlikely => Tone.danger,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.brand),
              const SizedBox(width: Space.xs),
              Text(
                'Gemini assessment',
                style: t.labelMedium?.copyWith(color: AppColors.brand),
              ),
              const Spacer(),
              StatusBadge(a.eligibility.label, tone: tone),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(a.summary, style: t.bodyMedium),
          if (a.requiredInformation.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('Merchant will likely need', style: t.titleSmall),
            for (final i in a.requiredInformation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: AppColors.brand,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(i, style: t.bodySmall)),
                  ],
                ),
              ),
          ],
          if (a.missingInformation.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('Missing from your request', style: t.titleSmall),
            for (final i in a.missingInformation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.priority_high_rounded,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(i, style: t.bodySmall)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Space.md),
          Text('Draft message', style: t.titleSmall),
          const SizedBox(height: Space.xxs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: SelectableText(a.draftMessage, style: t.bodySmall),
          ),
          const SizedBox(height: Space.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: a.draftMessage));
                  if (context.mounted) showMessage(context, 'Copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy'),
              ),
              TextButton.icon(
                onPressed: () =>
                    SharePlus.instance.share(ShareParams(text: a.draftMessage)),
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: const Text('Send'),
              ),
            ],
          ),
          Text(
            'This is guidance, not a decision. Only the merchant can approve a refund.',
            style: t.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

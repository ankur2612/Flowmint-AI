import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../utils/json_read.dart';
import '../utils/money.dart';
import 'gemini_service.dart';

/// Fields Gemini read from a bill or receipt image. Every value is a
/// suggestion the user must review before it is used.
class ReceiptExtraction {
  const ReceiptExtraction({
    required this.isReceipt,
    this.merchant,
    this.totalMinor,
    this.currency = AppConstants.defaultCurrency,
    this.purchaseDate,
    this.orderReference,
    this.items = const [],
    this.subtotalMinor,
    this.taxMinor,
    this.tipMinor,
    this.discountMinor,
    this.billingCycle,
    this.nextBillingDate,
  });

  final bool isReceipt;
  final String? merchant;
  final int? totalMinor;
  final String currency;
  final DateTime? purchaseDate;
  final String? orderReference;
  final List<String> items;
  final int? subtotalMinor;
  final int? taxMinor;
  final int? tipMinor;
  final int? discountMinor;

  /// weekly, monthly, quarterly or yearly when the document is a recurring
  /// subscription invoice.
  final String? billingCycle;
  final DateTime? nextBillingDate;

  factory ReceiptExtraction.fromJson(Map<String, dynamic> j) {
    final currency = Read.strOrNull(j['currency'])?.toUpperCase();
    return ReceiptExtraction(
      isReceipt: Read.boolean(j['isReceipt']),
      merchant: Read.strOrNull(j['merchant']),
      totalMinor: Money.fromMajor(Read.number(j['total'])),
      currency: currency != null && RegExp(r'^[A-Z]{3}$').hasMatch(currency)
          ? currency
          : AppConstants.defaultCurrency,
      purchaseDate: Read.date(j['purchaseDate']),
      orderReference: Read.strOrNull(j['orderReference']),
      items: Read.strings(j['items']),
      subtotalMinor: Money.fromMajor(Read.number(j['subtotal'])),
      taxMinor: Money.fromMajor(Read.number(j['tax'])),
      tipMinor: Money.fromMajor(Read.number(j['tip'])),
      discountMinor: Money.fromMajor(Read.number(j['discount'])),
      billingCycle:
          const {
            'weekly',
            'monthly',
            'quarterly',
            'yearly',
          }.contains(Read.strOrNull(j['billingCycle']))
          ? Read.strOrNull(j['billingCycle'])
          : null,
      nextBillingDate: Read.date(j['nextBillingDate']),
    );
  }
}

class ReceiptAi {
  ReceiptAi(this._gemini);
  final GeminiService _gemini;

  static final _schema = Schema.object(
    properties: {
      'isReceipt': Schema.boolean(
        description: 'True only if the image is a bill, invoice or receipt.',
      ),
      'merchant': Schema.string(nullable: true),
      'total': Schema.number(
        nullable: true,
        description: 'Final amount payable, in major currency units.',
      ),
      'currency': Schema.string(
        nullable: true,
        description: 'ISO 4217 code, e.g. INR, USD.',
      ),
      'purchaseDate': Schema.string(
        nullable: true,
        description: 'ISO 8601 date (YYYY-MM-DD) if printed.',
      ),
      'orderReference': Schema.string(
        nullable: true,
        description: 'Order, invoice or transaction number if printed.',
      ),
      'subtotal': Schema.number(nullable: true, description: 'Before tax/tip.'),
      'tax': Schema.number(nullable: true, description: 'Total tax / GST.'),
      'tip': Schema.number(
        nullable: true,
        description: 'Tip or service charge.',
      ),
      'discount': Schema.number(nullable: true),
      'billingCycle': Schema.enumString(
        enumValues: ['weekly', 'monthly', 'quarterly', 'yearly', 'none'],
        nullable: true,
        description: 'Billing period if this is a recurring subscription.',
      ),
      'nextBillingDate': Schema.string(
        nullable: true,
        description: 'Next renewal / billing date (YYYY-MM-DD) if printed.',
      ),
      'items': Schema.array(
        items: Schema.string(),
        description: 'Short line-item descriptions, at most 15.',
      ),
    },
    optionalProperties: [
      'merchant',
      'total',
      'currency',
      'purchaseDate',
      'orderReference',
      'subtotal',
      'tax',
      'tip',
      'discount',
      'billingCycle',
      'nextBillingDate',
    ],
  );

  Future<ReceiptExtraction> extract(AiDocument image) async {
    final json = await _gemini.generateJson(
      instruction:
          'You read bills, receipts and invoices (photos or PDFs). Report only what is printed on the '
          'document. Never guess values that are not visible; use null instead.',
      prompt: 'Extract the receipt or bill details from this document.',
      schema: _schema,
      document: image,
      temperature: 0,
    );
    return ReceiptExtraction.fromJson(json);
  }
}

final receiptAiProvider = Provider<ReceiptAi>(
  (ref) => ReceiptAi(ref.watch(geminiServiceProvider)),
);

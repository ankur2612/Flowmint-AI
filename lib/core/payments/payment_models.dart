import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/json_read.dart';

enum PaymentKind {
  shopping('shopping', 'orders'),
  donation('donation', 'donations');

  const PaymentKind(this.wire, this.collection);
  final String wire;
  final String collection;

  static PaymentKind fromWire(String v) =>
      values.firstWhere((k) => k.wire == v, orElse: () => shopping);
}

/// Server-owned status of a PayPal-backed record. Only Cloud Functions write
/// these values, after verifying them with PayPal.
enum PaymentStatus {
  created('Awaiting approval'),
  pending('Pending'),
  completed('Paid'),
  failed('Failed'),
  cancelled('Cancelled'),
  refunded('Refunded'),
  partiallyRefunded('Partially refunded');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus fromWire(String? v) => switch (v) {
    'COMPLETED' => completed,
    // Approved by the buyer or capture in progress: not paid until PayPal
    // confirms the capture.
    'PENDING' || 'APPROVED' || 'CAPTURE_PENDING' => pending,
    'FAILED' || 'DENIED' => failed,
    'CANCELLED' || 'VOIDED' => cancelled,
    'REFUNDED' => refunded,
    'PARTIALLY_REFUNDED' => partiallyRefunded,
    _ => created,
  };

  bool get isFinal => this != created && this != pending;
}

class PaymentLineItem {
  const PaymentLineItem({
    required this.productId,
    required this.quantity,
    this.name = '',
    this.unitPriceMinor = 0,
  });

  final String productId;
  final int quantity;
  final String name;
  final int unitPriceMinor;

  factory PaymentLineItem.fromMap(Map<String, dynamic> m) => PaymentLineItem(
    productId: Read.str(m['productId']),
    quantity: Read.integer(m['quantity'], 1),
    name: Read.str(m['name']),
    unitPriceMinor: Read.integer(m['unitPriceMinor']),
  );
}

/// A shopping order or donation as recorded by the trusted backend.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.kind,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.description,
    this.items = const [],
    this.campaignTitle,
    this.recipient,
    this.paypalOrderId,
    this.captureId,
    this.createdAt,
    this.completedAt,
    this.refundStatus,
    this.refundedMinor = 0,
    this.failureReason,
  });

  final String id;
  final PaymentKind kind;
  final PaymentStatus status;
  final int amountMinor;
  final String currency;
  final String description;
  final List<PaymentLineItem> items;
  final String? campaignTitle;
  final String? recipient;
  final String? paypalOrderId;
  final String? captureId;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? refundStatus;
  final int refundedMinor;
  final String? failureReason;

  factory PaymentRecord.fromDoc(
    PaymentKind kind,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? const {};
    return PaymentRecord(
      id: doc.id,
      kind: kind,
      status: PaymentStatus.fromWire(Read.strOrNull(m['status'])),
      amountMinor: Read.integer(m['amountMinor']),
      currency: Read.str(m['currency'], 'USD'),
      description: Read.str(m['description']),
      items: Read.maps(m['items']).map(PaymentLineItem.fromMap).toList(),
      campaignTitle: Read.strOrNull(m['campaignTitle']),
      recipient: Read.strOrNull(m['recipient']),
      paypalOrderId: Read.strOrNull(m['paypalOrderId']),
      captureId: Read.strOrNull(m['captureId']),
      createdAt: Read.date(m['createdAt']),
      completedAt: Read.date(m['completedAt']),
      refundStatus: Read.strOrNull(m['refundStatus']),
      refundedMinor: Read.integer(m['refundedMinor']),
      failureReason: Read.strOrNull(m['failureReason']),
    );
  }
}

/// What the client asks the backend to charge for. Amounts for shopping are
/// never sent: the server prices items from the catalogue.
sealed class CheckoutRequest {
  const CheckoutRequest(this.idempotencyKey);
  final String idempotencyKey;
  PaymentKind get kind;
  Map<String, dynamic> toPayload();
}

class ShoppingCheckoutRequest extends CheckoutRequest {
  const ShoppingCheckoutRequest(super.idempotencyKey, this.items);
  final List<PaymentLineItem> items;

  @override
  PaymentKind get kind => PaymentKind.shopping;

  @override
  Map<String, dynamic> toPayload() => {
    'kind': kind.wire,
    'idempotencyKey': idempotencyKey,
    'items': [
      for (final i in items) {'productId': i.productId, 'quantity': i.quantity},
    ],
  };
}

class DonationCheckoutRequest extends CheckoutRequest {
  const DonationCheckoutRequest(
    super.idempotencyKey, {
    required this.campaignId,
    required this.amountMinor,
  });
  final String campaignId;
  final int amountMinor;

  @override
  PaymentKind get kind => PaymentKind.donation;

  @override
  Map<String, dynamic> toPayload() => {
    'kind': kind.wire,
    'idempotencyKey': idempotencyKey,
    'campaignId': campaignId,
    'amountMinor': amountMinor,
  };
}

/// A PayPal order created by the backend, awaiting buyer approval.
class CheckoutSession {
  const CheckoutSession({
    required this.recordId,
    required this.kind,
    required this.paypalOrderId,
    required this.approveUrl,
    required this.returnUrl,
    required this.cancelUrl,
    required this.amountMinor,
    required this.currency,
    required this.status,
  });

  final String recordId;
  final PaymentKind kind;
  final String paypalOrderId;
  final String approveUrl;
  final String returnUrl;
  final String cancelUrl;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;

  factory CheckoutSession.fromMap(Map<String, dynamic> m) => CheckoutSession(
    recordId: Read.str(m['recordId']),
    kind: PaymentKind.fromWire(Read.str(m['kind'])),
    paypalOrderId: Read.str(m['paypalOrderId']),
    approveUrl: Read.str(m['approveUrl']),
    returnUrl: Read.str(m['returnUrl']),
    cancelUrl: Read.str(m['cancelUrl']),
    amountMinor: Read.integer(m['amountMinor']),
    currency: Read.str(m['currency']),
    status: PaymentStatus.fromWire(Read.strOrNull(m['status'])),
  );
}

/// Details shown on the mandatory confirmation screen before any payment.
class PaymentReview {
  const PaymentReview({
    required this.title,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.recipient,
    this.details = const [],
  });

  final String title;
  final String description;
  final int amountMinor;
  final String currency;
  final String recipient;
  final List<(String, String)> details;
}

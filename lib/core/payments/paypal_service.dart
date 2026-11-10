import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../utils/json_read.dart';
import 'payment_models.dart';

class PaymentException implements Exception {
  const PaymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client side of the PayPal integration. All PayPal API calls happen inside
/// Python Cloud Functions that hold the credentials; this class only invokes
/// them and reads the records they write.
class PayPalService {
  PayPalService(this._functions, this._userDoc);
  final FirebaseFunctions _functions;
  final DocumentReference<Map<String, dynamic>>? _userDoc;

  Future<CheckoutSession> createOrder(CheckoutRequest request) async {
    final data = await _call('create_paypal_order', request.toPayload());
    final session = CheckoutSession.fromMap(data);
    if (session.approveUrl.isEmpty && !session.status.isFinal) {
      throw const PaymentException('PayPal did not return an approval link.');
    }
    return session;
  }

  /// Asks the backend to capture an approved order. The returned status is
  /// what PayPal reported to the backend, never what the WebView suggested.
  Future<PaymentStatus> capture(CheckoutSession session) async {
    final data = await _call('capture_paypal_order', {
      'kind': session.kind.wire,
      'recordId': session.recordId,
    });
    return PaymentStatus.fromWire(Read.strOrNull(data['status']));
  }

  Future<void> cancel(CheckoutSession session) async {
    try {
      await _call('cancel_paypal_order', {
        'kind': session.kind.wire,
        'recordId': session.recordId,
      });
    } catch (_) {
      // An unapproved PayPal order simply expires; cancelling is best effort.
    }
  }

  /// Requests a refund of a FLOWMINT shopping order captured through PayPal.
  /// Eligibility (ownership, status, refund window) is enforced server-side.
  Future<String> refundOrder(String orderId, {required String reason}) async {
    final data = await _call('refund_paypal_order', {
      'recordId': orderId,
      'reason': reason,
    });
    return Read.str(data['status'], 'PENDING');
  }

  Stream<PaymentRecord?> watch(PaymentKind kind, String id) {
    final doc = _userDoc;
    if (doc == null) return const Stream.empty();
    return doc
        .collection(kind.collection)
        .doc(id)
        .snapshots()
        .map((s) => s.exists ? PaymentRecord.fromDoc(kind, s) : null);
  }

  Stream<List<PaymentRecord>> watchAll(PaymentKind kind) {
    final doc = _userDoc;
    if (doc == null) return const Stream.empty();
    return doc
        .collection(kind.collection)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => q.docs.map((d) => PaymentRecord.fromDoc(kind, d)).toList());
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 40)),
          )
          .call<Map<String, dynamic>>(payload);
      return Read.map(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw PaymentException(switch (e.code) {
        'unauthenticated' => 'Please sign in again to continue.',
        // An undeployed function surfaces as a bare NOT_FOUND.
        'not-found' when e.message == null || e.message == 'NOT_FOUND' =>
          'Payments are not set up yet. Deploy the FLOWMINT Cloud Functions.',
        'unavailable' || 'deadline-exceeded' =>
          'PayPal could not be reached. Check your connection and try again.',
        _ => e.message ?? 'The payment could not be processed.',
      });
    } catch (_) {
      throw const PaymentException(
        'The payment service could not be reached. Please try again.',
      );
    }
  }
}

final paypalServiceProvider = Provider<PayPalService>(
  (ref) =>
      PayPalService(ref.watch(functionsProvider), ref.watch(userDocProvider)),
);

final paymentRecordProvider = StreamProvider.autoDispose
    .family<PaymentRecord?, (PaymentKind, String)>(
      (ref, key) => ref.watch(paypalServiceProvider).watch(key.$1, key.$2),
    );

final paymentRecordsProvider = StreamProvider.autoDispose
    .family<List<PaymentRecord>, PaymentKind>(
      (ref, kind) => ref.watch(paypalServiceProvider).watchAll(kind),
    );

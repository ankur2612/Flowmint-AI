import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

/// Global messenger so foreground push messages and app-level notices can be
/// surfaced from outside the widget tree.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Registers the device for Firebase Cloud Messaging and stores the token on
/// the user profile. Cloud Functions read these tokens to send payment and
/// renewal notifications.
///
/// This deliberately uses FCM registration tokens rather than the newer
/// installation-ID (FID) direct-send API: the Python Admin SDK used by the
/// backend targets registration tokens.
class NotificationService {
  NotificationService(this._messaging, this._firestore);
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  String? _registeredUid;

  Future<bool> register(String uid) async {
    if (_registeredUid == uid) return true;
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(uid, token);
      await _refreshSub?.cancel();
      // ignore: deprecated_member_use
      _refreshSub = _messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(_showForeground);
      _registeredUid = uid;
      return true;
    } catch (_) {
      // Messaging is optional; the app remains fully usable without it.
      return false;
    }
  }

  Future<void> unregister(String uid) async {
    try {
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
    } catch (_) {
      // Best effort: stale tokens are pruned server-side on send failure.
    }
    await _refreshSub?.cancel();
    await _foregroundSub?.cancel();
    _registeredUid = null;
  }

  Future<void> _saveToken(String uid, String token) =>
      _firestore.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));

  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text([n.title, n.body].whereType<String>().join(' — ')),
      ),
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(
    FirebaseMessaging.instance,
    ref.watch(firestoreProvider),
  ),
);

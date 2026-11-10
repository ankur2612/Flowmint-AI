import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_providers.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._auth, this._firestore);
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool _googleInitialised = false;

  Future<void> signIn({required String email, required String password}) =>
      _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        await _ensureProfile(cred.user!);
      });

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user!.updateDisplayName(name.trim());
    await _ensureProfile(cred.user!, displayName: name.trim());
  });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> signInWithGoogle() => _guard(() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialised) {
      await google.initialize(
        serverClientId: AppConstants.googleServerClientId.isEmpty
            ? null
            : AppConstants.googleServerClientId,
      );
      _googleInitialised = true;
    }
    if (!google.supportsAuthenticate()) {
      throw const AuthException(
        'Google sign-in is not supported on this device.',
      );
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return a sign-in token.');
    }
    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
    await _ensureProfile(cred.user!);
  });

  Future<void> signOut() async {
    if (_googleInitialised) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out below is what ends the FLOWMINT session.
      }
    }
    await _auth.signOut();
  }

  Future<void> _ensureProfile(User user, {String? displayName}) async {
    final doc = _firestore.collection('users').doc(user.uid);
    final snap = await doc.get();
    if (snap.exists) return;
    await doc.set({
      'displayName': displayName ?? user.displayName ?? '',
      'email': user.email,
      'notifyPayments': true,
      'notifyRenewals': true,
      'notifyActivity': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(describeAuthError(e.code));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Google sign-in was cancelled.');
      }
      throw const AuthException(
        'Google sign-in is unavailable. Check that it is enabled for this Firebase project.',
      );
    } on FirebaseException {
      throw const AuthException(
        'Your profile could not be loaded. Please try again.',
      );
    }
  }
}

String describeAuthError(String code) => switch (code) {
  'invalid-email' => 'That email address looks invalid.',
  'user-disabled' => 'This account has been disabled.',
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Incorrect email or password.',
  'email-already-in-use' => 'An account already exists for that email.',
  'weak-password' => 'Choose a stronger password (at least 8 characters).',
  'too-many-requests' => 'Too many attempts. Please wait and try again.',
  'network-request-failed' =>
    'No connection. Check your network and try again.',
  'operation-not-allowed' =>
    'This sign-in method is not enabled for the FLOWMINT Firebase project.',
  'requires-recent-login' => 'Please sign in again to continue.',
  _ => 'Authentication failed. Please try again.',
};

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  ),
);

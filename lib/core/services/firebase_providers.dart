import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

/// Cloud Functions client. When built with
/// `--dart-define=FUNCTIONS_EMULATOR_HOST=<laptop Wi-Fi IP>` it talks to the
/// local Firebase emulator, so PayPal works on the free Spark plan without
/// deploying functions.
final functionsProvider = Provider<FirebaseFunctions>((_) {
  final functions = FirebaseFunctions.instanceFor(
    region: AppConstants.functionsRegion,
  );
  const host = AppConstants.functionsEmulatorHost;
  if (host.isNotEmpty) functions.useFunctionsEmulator(host, 5001);
  return functions;
});

final firebaseAiProvider = Provider<FirebaseAI>((_) => FirebaseAI.googleAI());

/// Overridden in `main.dart` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw StateError('SharedPreferences not initialised'),
);

/// This device's App Check debug token in debug builds; always null in
/// release builds. Overridden in `main.dart`.
final appCheckDebugTokenProvider = Provider<String?>((_) => null);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).userChanges(),
);

/// The signed-in user's id, or null while signed out.
final uidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);

/// Root document for all of the signed-in user's private records, or null
/// while signed out. Repositories depend on this so they are rebuilt when the
/// signed-in user changes.
final userDocProvider = Provider<DocumentReference<Map<String, dynamic>>?>((
  ref,
) {
  final uid = ref.watch(uidProvider);
  return uid == null
      ? null
      : ref.watch(firestoreProvider).collection('users').doc(uid);
});

/// Base for repositories scoped to the signed-in user.
abstract class UserScopedRepository {
  const UserScopedRepository(this._userDoc);
  final DocumentReference<Map<String, dynamic>>? _userDoc;

  DocumentReference<Map<String, dynamic>> get user {
    final doc = _userDoc;
    if (doc == null) throw StateError('Sign in to continue.');
    return doc;
  }

  bool get isSignedIn => _userDoc != null;

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      user.collection(name);
}

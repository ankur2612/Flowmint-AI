import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'core/services/firebase_providers.dart';

const _debugTokenKey = 'app_check_debug_token';

/// App Check mode, chosen at build time (not a secret):
/// - '' (default): not activated. Required while App Check is unenforced for
///   Firebase AI Logic, because an App Check token that cannot be obtained
///   (unregistered debug token, or Play Integrity on a sideloaded APK) makes
///   the Gemini SDK abort every request.
/// - 'debug': debug provider, honoured only in debug builds.
/// - 'play_integrity': for apps distributed through Google Play.
const _appCheckMode = String.fromEnvironment('APP_CHECK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // On Android, Firebase options come from android/app/google-services.json.
  // Without it the app shows a setup screen instead of failing silently.
  Object? firebaseError;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    firebaseError = e;
  }

  // Order matters: Firebase is initialised above, App Check (when enabled)
  // is activated here, and Firebase AI Logic is only created lazily
  // (firebaseAiProvider) on the first Gemini request.
  final useDebugProvider = kDebugMode && _appCheckMode == 'debug';
  final usePlayIntegrity = !kDebugMode && _appCheckMode == 'play_integrity';
  String? debugToken;
  if (firebaseError == null && (useDebugProvider || usePlayIntegrity)) {
    if (useDebugProvider) {
      // Random per-device token kept only in local storage and shown in
      // Profile for registration; never in source or build configuration.
      debugToken = prefs.getString(_debugTokenKey);
      if (debugToken == null) {
        debugToken = const Uuid().v4();
        await prefs.setString(_debugTokenKey, debugToken);
      }
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugProvider
            ? AndroidDebugProvider(debugToken: debugToken)
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (_) {
      // Surfaced by the assistant as an error instead of blocking startup.
    }
  }

  runApp(
    firebaseError != null
        ? const FirebaseSetupRequiredApp()
        : ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              appCheckDebugTokenProvider.overrideWithValue(debugToken),
            ],
            child: const FlowmintApp(),
          ),
  );
}

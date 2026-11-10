/// Application-wide configuration. Values that differ per environment are
/// read from `--dart-define` so no credentials are compiled into source.
abstract final class AppConstants {
  static const appName = 'FLOWMINT';

  /// Gemini model used through Firebase AI Logic (Gemini Developer API).
  /// Verified on the free tier on 2026-11-10: gemini-3.5-flash-lite supports
  /// structured JSON, image and PDF input. gemini-3.8-flash allows only 20
  /// free requests per project per day, too few for this app.
  static const geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  /// Used automatically when the primary model is overloaded or unavailable.
  static const geminiFallbackModel = 'gemini-flash-lite-latest';

  /// Region the Python Cloud Functions are deployed to.
  static const functionsRegion = String.fromEnvironment(
    'FUNCTIONS_REGION',
    defaultValue: 'asia-south1',
  );

  /// Laptop address running `firebase emulators:start --only functions`.
  /// Empty means deployed Cloud Functions are used.
  static const functionsEmulatorHost = String.fromEnvironment(
    'FUNCTIONS_EMULATOR_HOST',
  );

  /// Optional OAuth web client ID for Google sign-in. When empty the Android
  /// plugin falls back to `default_web_client_id` from google-services.json.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Currency used for amounts the user types in (splits, quotes,
  /// subscriptions). Checkout currency always comes from server data.
  static const defaultCurrency = 'INR';

  /// Display name of the PayPal merchant account that receives shop orders.
  static const merchantName = String.fromEnvironment(
    'MERCHANT_NAME',
    defaultValue: 'FLOWMINT Store',
  );

  /// Shown on payment review screens so testers know no real money moves.
  static const paypalEnvironment = String.fromEnvironment(
    'PAYPAL_ENV',
    defaultValue: 'sandbox',
  );

  static bool get isSandbox => paypalEnvironment != 'live';

  static const maxUploadBytes = 10 * 1024 * 1024;

  /// Upper bound for any amount typed by a user, in major units.
  static const maxUserAmount = 10000000;
}

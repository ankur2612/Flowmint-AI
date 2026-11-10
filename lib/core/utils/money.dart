import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Money is always handled as integer minor units (paise, cents) to avoid
/// floating point drift in financial calculations.
abstract final class Money {
  static String format(
    int minor, {
    String currency = AppConstants.defaultCurrency,
    bool compact = false,
  }) {
    final hasFraction = minor % 100 != 0;
    final formatter = NumberFormat.simpleCurrency(
      name: currency,
      locale: currency == 'INR' ? 'en_IN' : 'en_US',
      decimalDigits: hasFraction && !compact ? 2 : 0,
    );
    return formatter.format(minor / 100);
  }

  /// Formats with the ISO code ("INR 2,400.00"), for documents whose fonts
  /// may not contain currency symbols.
  static String formatWithCode(int minor, String currency) =>
      NumberFormat.currency(
        locale: currency == 'INR' ? 'en_IN' : 'en_US',
        symbol: '$currency ',
        decimalDigits: 2,
      ).format(minor / 100);

  static String symbol(String currency) =>
      NumberFormat.simpleCurrency(name: currency).currencySymbol;

  /// Parses user input like "2,400", "₹2400.50" or "1200.5" into minor units.
  /// Returns null for empty, negative, malformed or out-of-range values.
  static int? parseToMinor(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty || input.contains('-')) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
    final value = double.parse(cleaned);
    if (value > AppConstants.maxUserAmount) return null;
    return (value * 100).round();
  }

  /// Converts a major-unit amount (as returned by AI extraction) to minor
  /// units, rejecting non-positive or implausible values.
  static int? fromMajor(num? value) {
    if (value == null || value.isNaN || value <= 0) return null;
    if (value > AppConstants.maxUserAmount) return null;
    return (value * 100).round();
  }

  /// Plain editable representation (no symbol, no grouping).
  static String toInput(int minor) {
    if (minor % 100 == 0) return (minor ~/ 100).toString();
    return (minor / 100).toStringAsFixed(2);
  }
}

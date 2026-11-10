import 'package:cloud_firestore/cloud_firestore.dart';

/// Defensive readers for Firestore documents and AI JSON payloads, which
/// may contain missing fields or unexpected types.
abstract final class Read {
  static String str(Object? v, [String fallback = '']) =>
      v is String ? v : (v == null ? fallback : v.toString());

  static String? strOrNull(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static int integer(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static double? number(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool boolean(Object? v, [bool fallback = false]) =>
      v is bool ? v : fallback;

  static DateTime? date(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static List<Map<String, dynamic>> maps(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static List<String> strings(Object? v) {
    if (v is! List) return const [];
    return v.map(strOrNull).whereType<String>().toList(growable: false);
  }

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}

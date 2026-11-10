import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'firebase_providers.dart';

/// A document (bill, receipt, invoice, specification) passed to Gemini.
/// Images and PDFs are sent inline; nothing is uploaded or stored.
class AiDocument {
  const AiDocument(this.bytes, this.mimeType, {this.name});

  final Uint8List bytes;
  final String mimeType;
  final String? name;

  bool get isPdf => mimeType == 'application/pdf';

  static const supportedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/pdf',
  };
}

enum AiErrorKind {
  quota,
  overloaded,
  timeout,
  network,
  invalidResponse,
  setup,
  input,
  rateLimited,
  other,
}

class AiException implements Exception {
  const AiException(this.message, {this.kind = AiErrorKind.other});
  final String message;
  final AiErrorKind kind;

  /// Whether retrying the same request could succeed.
  bool get retryable => kind != AiErrorKind.setup && kind != AiErrorKind.input;

  @override
  String toString() => message;
}

/// Central boundary over Firebase AI Logic (Gemini Developer API, free tier).
///
/// Every call requests JSON constrained by a response schema, is bounded by
/// a per-attempt timeout, retries once on a fallback model when the primary
/// is overloaded or unavailable, and is rate-limited on the device to stay
/// within free-tier quotas. A request can therefore never load forever.
class GeminiService {
  GeminiService(this._ai);
  final FirebaseAI _ai;

  static const _attemptTimeout = Duration(seconds: 30);
  static const _maxRequestsPerMinute = 12;
  static const maxDocumentBytes = 7 * 1024 * 1024;
  static final List<DateTime> _recent = [];

  Future<Map<String, dynamic>> generateJson({
    required String instruction,
    required String prompt,
    required Schema schema,
    List<Content> history = const [],
    AiDocument? document,
    double temperature = 0.2,
  }) async {
    _validateInput(prompt, document);
    _reserveSlot();

    final parts = <Part>[
      if (document != null) InlineDataPart(document.mimeType, document.bytes),
      TextPart(prompt),
    ];
    final request = [...history, Content.multi(parts)];
    final models = {
      AppConstants.geminiModel,
      AppConstants.geminiFallbackModel,
    }.toList();

    AiException? last;
    for (var i = 0; i < models.length; i++) {
      try {
        return await _attempt(
          models[i],
          instruction,
          schema,
          temperature,
          request,
        );
      } on AiException catch (e) {
        last = e;
        final tryNext =
            e.kind == AiErrorKind.overloaded || e.kind == AiErrorKind.timeout;
        if (!tryNext || i == models.length - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    throw last ??
        const AiException('The assistant could not respond. Please try again.');
  }

  Future<Map<String, dynamic>> _attempt(
    String modelName,
    String instruction,
    Schema schema,
    double temperature,
    List<Content> request,
  ) async {
    final model = _ai.generativeModel(
      model: modelName,
      systemInstruction: Content.system(instruction),
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: schema,
        temperature: temperature,
        maxOutputTokens: 2048,
      ),
    );
    try {
      final response = await model
          .generateContent(request)
          .timeout(_attemptTimeout);
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        throw const AiException(
          'Gemini returned an empty response. Please try again.',
          kind: AiErrorKind.invalidResponse,
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object');
      }
      return Map<String, dynamic>.from(decoded);
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException(
        'Gemini is taking too long to respond. Check your connection and try again.',
        kind: AiErrorKind.timeout,
      );
    } on FormatException {
      throw const AiException(
        'Gemini returned an unexpected response. Please try again.',
        kind: AiErrorKind.invalidResponse,
      );
    } on QuotaExceeded {
      throw const AiException(
        "Today's free Gemini quota has been reached. Please try again later.",
        kind: AiErrorKind.quota,
      );
    } on ServiceApiNotEnabled {
      throw const AiException(
        'Firebase AI Logic is not enabled for this Firebase project.',
        kind: AiErrorKind.setup,
      );
    } on InvalidApiKey {
      throw const AiException(
        'The Firebase API key is not valid for Gemini. Check the Firebase configuration.',
        kind: AiErrorKind.setup,
      );
    } on ServerException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('not found') ||
          m.contains('high demand') ||
          m.contains('overloaded') ||
          m.contains('unavailable') ||
          m.contains('internal')) {
        throw const AiException(
          'Gemini is busy right now. Please try again in a moment.',
          kind: AiErrorKind.overloaded,
        );
      }
      if (m.contains('app check') || m.contains('appcheck')) {
        throw const AiException(
          'Gemini rejected this device (App Check). Check App Check settings for Firebase AI Logic.',
          kind: AiErrorKind.setup,
        );
      }
      throw const AiException(
        'Gemini could not complete this request. Please try again.',
      );
    } on FirebaseAIException {
      throw const AiException(
        'Gemini could not complete this request. Please try again.',
      );
    } catch (_) {
      throw const AiException(
        'Could not reach Gemini. Check your internet connection and try again.',
        kind: AiErrorKind.network,
      );
    }
  }

  void _validateInput(String prompt, AiDocument? document) {
    if (prompt.length > 8000) {
      throw const AiException(
        'That message is too long. Please shorten it.',
        kind: AiErrorKind.input,
      );
    }
    if (document == null) return;
    if (!AiDocument.supportedMimeTypes.contains(document.mimeType)) {
      throw const AiException(
        'Only images (JPEG, PNG, WebP, HEIC) and PDFs are supported.',
        kind: AiErrorKind.input,
      );
    }
    if (document.bytes.lengthInBytes > maxDocumentBytes) {
      throw const AiException(
        'Documents must be smaller than 7 MB.',
        kind: AiErrorKind.input,
      );
    }
  }

  /// Keeps usage within free-tier limits by capping requests per minute.
  void _reserveSlot() {
    final now = DateTime.now();
    _recent.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_recent.length >= _maxRequestsPerMinute) {
      final wait = 60 - now.difference(_recent.first).inSeconds;
      throw AiException(
        'You are sending requests quickly. Please wait $wait seconds.',
        kind: AiErrorKind.rateLimited,
      );
    }
    _recent.add(now);
  }
}

final geminiServiceProvider = Provider<GeminiService>(
  (ref) => GeminiService(ref.watch(firebaseAiProvider)),
);

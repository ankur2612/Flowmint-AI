import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import 'assistant_models.dart';

/// Persists the assistant conversation at
/// `users/{uid}/conversations/main/messages`.
class AssistantRepository extends UserScopedRepository {
  AssistantRepository(super.userDoc);

  final _completions = StreamController<(String, String)>.broadcast();

  /// Emits (messageId, resultRoute) whenever a prepared action is completed
  /// from a module screen, so the live conversation can update.
  Stream<(String, String)> get completions => _completions.stream;

  CollectionReference<Map<String, dynamic>> get _messages =>
      user.collection('conversations').doc('main').collection('messages');

  Future<List<ChatMessage>> loadRecent({int limit = 60}) async {
    final q = await _messages
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return q.docs.reversed.map(ChatMessage.fromDoc).toList();
  }

  Future<void> save(ChatMessage message) =>
      _messages.doc(message.id).set(message.toMap());

  /// Records that the action prepared in [messageId] was completed, so the
  /// action card shows the result instead of offering to create it again.
  Future<void> markActionCompleted(String messageId, String route) async {
    _completions.add((messageId, route));
    await _messages.doc(messageId).update({'actionCompletedRoute': route});
  }

  /// Deletes the stored conversation (privacy control).
  Future<void> clear() async {
    while (true) {
      final page = await _messages.limit(200).get();
      if (page.docs.isEmpty) return;
      final batch = user.firestore.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  void dispose() => _completions.close();
}

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  final repo = AssistantRepository(ref.watch(userDocProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

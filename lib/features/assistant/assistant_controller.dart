import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/gemini_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/state_views.dart';
import '../impact_giving/campaign_repository.dart';
import '../shopping/shopping_agent.dart';
import '../smart_quotes/quote_ai.dart';
import '../subscriptions/subscription_repository.dart';
import 'assistant_ai.dart';
import 'assistant_models.dart';
import 'assistant_repository.dart';

class AssistantState {
  const AssistantState({
    this.messages = const [],
    this.loading = false,
    this.thinking = false,
    this.loadError,
  });

  final List<ChatMessage> messages;
  final bool loading;
  final bool thinking;
  final String? loadError;

  AssistantState copyWith({
    List<ChatMessage>? messages,
    bool? loading,
    bool? thinking,
    String? loadError,
  }) => AssistantState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    thinking: thinking ?? this.thinking,
    loadError: loadError,
  );
}

class AssistantController extends Notifier<AssistantState> {
  /// Images attached in this session, keyed by message id, so action cards
  /// can hand a bill or receipt to the module that processes it. Images are
  /// not persisted with the conversation.
  final _images = <String, AiDocument>{};
  StreamSubscription<(String, String)>? _completionSub;

  @override
  AssistantState build() {
    final repo = ref.watch(assistantRepositoryProvider);
    _images.clear();
    _completionSub?.cancel();
    _completionSub = repo.completions.listen(
      (e) => _applyCompletion(e.$1, e.$2),
    );
    ref.onDispose(() => _completionSub?.cancel());
    if (!repo.isSignedIn) return const AssistantState();
    Future.microtask(_load);
    return const AssistantState(loading: true);
  }

  AiDocument? documentFor(String messageId) => _images[messageId];

  Future<void> _load() async {
    try {
      final messages = await ref
          .read(assistantRepositoryProvider)
          .loadRecent()
          .timeout(const Duration(seconds: 15));
      state = state.copyWith(messages: messages, loading: false);
    } on TimeoutException {
      state = state.copyWith(
        loading: false,
        loadError:
            'Your conversation could not be loaded. Check your connection and try again.',
      );
    } catch (e) {
      state = state.copyWith(loading: false, loadError: friendlyError(e));
    }
  }

  void reload() {
    state = const AssistantState(loading: true);
    _load();
  }

  Future<void> send(String text, {AiDocument? image}) async {
    // Ignore taps while a request is in flight so one request can never
    // produce two prepared actions.
    if (state.thinking || state.loading) return;
    if (text.trim().isEmpty && image == null) return;
    final message = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.user,
      text: text.trim(),
      createdAt: DateTime.now(),
      hasImage: image != null,
    );
    if (image != null) _images[message.id] = image;
    state = state.copyWith(messages: [...state.messages, message]);
    _persist(message);
    await _respond(message);
  }

  Future<void> retry(ChatMessage error) async {
    if (state.thinking) return;
    final original = state.messages
        .where((m) => m.id == error.retryForMessageId)
        .firstOrNull;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != error.id).toList(),
    );
    if (original != null) await _respond(original);
  }

  Future<void> clear() async {
    await ref.read(assistantRepositoryProvider).clear();
    _images.clear();
    state = const AssistantState();
  }

  Future<void> _respond(ChatMessage request) async {
    state = state.copyWith(thinking: true);
    final image = _images[request.id];
    final history = state.messages
        .where((m) => m.id != request.id && !m.isError)
        .toList();
    try {
      final response = await ref
          .read(assistantAiProvider)
          .interpret(history: history, text: request.text, image: image);
      final (attachment, note) = await _runWorkflow(response, request.text);
      final reply = ChatMessage(
        id: const Uuid().v4(),
        role: ChatRole.assistant,
        text: note == null ? response.reply : '${response.reply}\n\n$note',
        createdAt: DateTime.now(),
        response: response,
        attachment: attachment,
      );
      if (image != null) _images[reply.id] = image;
      state = state.copyWith(
        messages: [...state.messages, reply],
        thinking: false,
      );
      _persist(reply);
    } catch (e) {
      final error = ChatMessage(
        id: const Uuid().v4(),
        role: ChatRole.assistant,
        text: e is AiException ? e.message : friendlyError(e),
        createdAt: DateTime.now(),
        retryForMessageId: request.id,
      );
      state = state.copyWith(
        messages: [...state.messages, error],
        thinking: false,
      );
    }
  }

  /// Runs the app-side part of the workflow Gemini selected, using real data
  /// only. Returns an attachment for the action card and an optional note.
  Future<(ActionAttachment?, String?)> _runWorkflow(
    AssistantResponse r,
    String userText,
  ) async {
    final p = r.parameters;
    try {
      switch (r.action) {
        case AssistantAction.searchProducts:
          final query = p.productQuery ?? userText;
          final result = await ref
              .read(shoppingAgentProvider)
              .recommend(
                query,
                maxBudgetMinor: p.maxBudgetMinor,
                budgetCurrency: p.currency,
              );
          return (
            ProductPicksAttachment(
              query: query,
              catalogueEmpty: result.catalogueEmpty,
              summary: result.summary,
              picks: [
                for (final rec in result.recommendations)
                  ProductPick(
                    rec.product.id,
                    rec.product.name,
                    rec.product.priceMinor,
                    rec.product.currency,
                    rec.reason,
                    rec.product.imageUrl,
                  ),
              ],
            ),
            null,
          );
        case AssistantAction.draftQuotation:
          final description = p.projectDescription;
          if (description == null) return (null, null);
          final seed = await ref
              .read(quoteAiProvider)
              .draft(description, clientName: p.clientName);
          return (QuoteDraftAttachment(seed), null);
        case AssistantAction.reviewSubscriptions:
          final subs = await ref
              .read(subscriptionRepositoryProvider)
              .fetchAll();
          final summary = SubscriptionSummary.compute(
            subs,
            today: DateTime.now(),
            window: 30,
          );
          final next = summary.upcoming.firstOrNull;
          return (
            SubscriptionSnapshotAttachment(
              monthlyMinor: summary.monthlyMinor,
              annualMinor: summary.annualMinor,
              activeCount: summary.activeCount,
              currency: p.currency,
              topCategory: summary.byCategory.firstOrNull?.key,
              nextRenewalName: next?.subscription.name,
              nextRenewalDate: next?.date,
            ),
            null,
          );
        case AssistantAction.prepareDonation:
          final campaigns = await ref
              .read(campaignRepositoryProvider)
              .fetchActive();
          final cause = p.cause;
          final matched = cause == null
              ? campaigns
              : campaigns.where((c) => c.matchesCause(cause)).toList();
          return (
            CampaignMatchesAttachment([
              for (final c in matched.take(3))
                CampaignMatch(c.id, c.title, c.organization),
            ]),
            null,
          );
        case AssistantAction.prepareSplit:
        case AssistantAction.prepareRefundRequest:
        case AssistantAction.none:
          return (null, null);
      }
    } on AiException catch (e) {
      return (null, "I couldn't finish preparing this: ${e.message}");
    } catch (e) {
      return (
        null,
        "I couldn't load the data for this step. ${friendlyError(e)}",
      );
    }
  }

  void _applyCompletion(String messageId, String route) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          m.id == messageId ? m.withCompletedRoute(route) : m,
      ],
    );
  }

  void _persist(ChatMessage m) {
    ref.read(assistantRepositoryProvider).save(m).catchError((Object _) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('This message could not be saved to your history.'),
        ),
      );
    });
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantState>(
      AssistantController.new,
    );

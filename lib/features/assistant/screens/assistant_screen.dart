import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/widgets/document_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../assistant_controller.dart';
import '../widgets/action_card.dart';
import '../widgets/chat_widgets.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.initialPrompt});

  /// Prompt passed from elsewhere in the app (e.g. Home quick actions).
  final String? initialPrompt;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  AiDocument? _image;
  String? _handledPrompt;
  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _textBeforeSpeech = '';

  /// On-device Android speech recognition (free, no cloud API). The
  /// microphone permission is requested only when the user taps the mic.
  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    try {
      _speechReady =
          _speechReady ||
          await _speech.initialize(
            onStatus: (status) {
              if ((status == 'done' || status == 'notListening') && mounted) {
                setState(() => _listening = false);
              }
            },
            onError: (_) {
              if (mounted) setState(() => _listening = false);
            },
          );
    } catch (_) {
      _speechReady = false;
    }
    if (!mounted) return;
    if (!_speechReady) {
      showMessage(
        context,
        'Voice input is unavailable. Allow microphone access, and make sure '
        'Google speech recognition is installed on this device.',
      );
      return;
    }
    _textBeforeSpeech = _input.text.trim();
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (r) {
        final spoken = r.recognizedWords;
        _input.text = [
          _textBeforeSpeech,
          spoken,
        ].where((t) => t.isNotEmpty).join(' ');
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleInitialPrompt());
  }

  @override
  void didUpdateWidget(covariant AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPrompt != oldWidget.initialPrompt) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleInitialPrompt(),
      );
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _handleInitialPrompt() async {
    final prompt = widget.initialPrompt?.trim();
    if (prompt == null || prompt.isEmpty || prompt == _handledPrompt) return;
    _handledPrompt = prompt;
    // Wait for history to load so the prompt is appended after it.
    while (ref.read(assistantControllerProvider).loading) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    await ref.read(assistantControllerProvider.notifier).send(prompt);
  }

  Future<void> _send([String? preset]) async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }
    final text = preset ?? _input.text;
    final image = preset == null ? _image : null;
    if (text.trim().isEmpty && image == null) return;
    if (preset == null) {
      _input.clear();
      setState(() => _image = null);
    }
    await ref
        .read(assistantControllerProvider.notifier)
        .send(text, image: image);
  }

  Future<void> _attach() async {
    final image = await pickDocument(context);
    if (image != null && mounted) {
      setState(() => _image = image);
      _focus.requestFocus();
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This deletes your assistant history. Records you saved (splits, quotes, orders) are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(assistantControllerProvider.notifier).clear();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);
    final messages = state.messages;

    Widget body;
    if (state.loading) {
      body = const LoadingView();
    } else if (state.loadError != null) {
      body = ErrorState(message: state.loadError!, onRetry: controller.reload);
    } else if (messages.isEmpty && !state.thinking) {
      body = AssistantWelcome(onPrompt: _send);
    } else {
      final itemCount = messages.length + (state.thinking ? 1 : 0);
      body = ListView.builder(
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.md,
          Space.gutter,
          Space.md,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (state.thinking && index == 0) return const TypingIndicator();
          final m =
              messages[messages.length -
                  1 -
                  (index - (state.thinking ? 1 : 0))];
          return MessageBubble(
            key: ValueKey(m.id),
            message: m,
            onRetry: m.isError && !state.thinking
                ? () => controller.retry(m)
                : null,
            child: m.response == null ? null : ActionCard(message: m),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: state.thinking ? null : _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: body,
            ),
          ),
          _Composer(
            controller: _input,
            focusNode: _focus,
            image: _image,
            busy: state.thinking || state.loading,
            onAttach: _attach,
            onRemoveImage: () => setState(() => _image = null),
            onSend: _send,
            listening: _listening,
            onMic: _toggleMic,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.image,
    required this.busy,
    required this.onAttach,
    required this.onRemoveImage,
    required this.onSend,
    required this.listening,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AiDocument? image;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onRemoveImage;
  final VoidCallback onSend;
  final bool listening;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final canSend =
        !busy && (controller.text.trim().isNotEmpty || image != null);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.sm,
        Space.xs,
        Space.sm,
        Space.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (image != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: DocumentChip(document: image!, onRemove: onRemoveImage),
            ),
          if (listening)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs, left: Space.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.brand,
                    size: 18,
                  ),
                  const SizedBox(width: Space.xs),
                  Text(
                    'Listening… tap the mic to stop. You can edit before sending.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.brand),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach photo or PDF',
                onPressed: busy ? null : onAttach,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => canSend ? onSend() : null,
                  decoration: InputDecoration(
                    hintText: 'Ask FLOWMINT anything financial…',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: const BorderSide(color: AppColors.brandMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.xs),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: canSend || listening
                      ? AppColors.brand
                      : AppColors.surfaceHighest,
                  shape: BoxShape.circle,
                ),
                child: canSend && !listening
                    ? IconButton(
                        tooltip: 'Send',
                        onPressed: onSend,
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          color: AppColors.onBrand,
                        ),
                      )
                    : IconButton(
                        tooltip: listening ? 'Stop listening' : 'Speak',
                        onPressed: busy ? null : onMic,
                        icon: Icon(
                          listening
                              ? Icons.stop_rounded
                              : Icons.mic_none_rounded,
                          color: listening
                              ? AppColors.onBrand
                              : AppColors.textSecondary,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/surfaces.dart';
import '../assistant_models.dart';

const suggestedPrompts = [
  (Icons.call_split_rounded, 'Split my restaurant bill between four people.'),
  (Icons.shopping_bag_outlined, 'Find a laptop under ₹60,000 for programming.'),
  (
    Icons.request_quote_outlined,
    'Prepare a quotation for a website development project.',
  ),
  (Icons.autorenew_rounded, 'Tell me how much I spend on subscriptions.'),
  (Icons.undo_rounded, 'Help me request a refund.'),
  (
    Icons.volunteer_activism_outlined,
    'I want to donate ₹500 towards education.',
  ),
];

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.child,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;

  /// Action card rendered under an assistant reply.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isUser = message.role == ChatRole.user;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: Space.sm, left: Space.xxl),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.brandSubtle,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(Radii.lg),
                topRight: Radius.circular(Radii.lg),
                bottomLeft: Radius.circular(Radii.lg),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.hasImage)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: message.text.isEmpty ? 0 : Space.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_file_rounded,
                          size: 15,
                          color: AppColors.brand,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Document attached',
                          style: t.labelMedium?.copyWith(
                            color: AppColors.brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (message.text.isNotEmpty)
                  Text(message.text, style: t.bodyMedium),
                const SizedBox(height: 2),
                _Timestamp(message.createdAt),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md, right: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: BrandMark(size: 26),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isError)
                  Container(
                    padding: const EdgeInsets.all(Space.sm),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: Space.xs),
                        Expanded(child: Text(message.text, style: t.bodySmall)),
                        if (onRetry != null)
                          TextButton(
                            onPressed: onRetry,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: _markdownStyle(context),
                    ),
                  ),
                if (!message.isError) ...[
                  const SizedBox(height: Space.xxs),
                  _Timestamp(message.createdAt),
                ],
                if (child != null) ...[
                  const SizedBox(height: Space.sm),
                  child!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FLOWMINT is thinking',
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Row(
          children: [
            const BrandMark(size: 26),
            const SizedBox(width: Space.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Opacity(
                          opacity:
                              0.3 +
                              0.7 *
                                  _pulse((_controller.value - i * 0.18) % 1.0),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _pulse(double v) => v < 0.5 ? v * 2 : (1 - v) * 2;
}

/// Intro shown when the conversation is empty.
class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({super.key, required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    var i = 0;
    return GlowBackdrop(
      intensity: 0.8,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.xl,
          Space.gutter,
          Space.lg,
        ),
        children: [
          FadeSlideIn(
            child: Container(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.3),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: const BrandMark(size: 48),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          FadeSlideIn(
            index: 1,
            child: Text('What would you like to do?', style: t.headlineMedium),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Describe it in your own words. I will prepare the right workflow — you review and approve every payment.',
            style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Space.xl),
          for (final (icon, prompt) in suggestedPrompts)
            FadeSlideIn(
              index: 2 + i++,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => onPrompt(prompt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 19, color: AppColors.brand),
                          const SizedBox(width: Space.sm),
                          Expanded(child: Text(prompt, style: t.bodyMedium)),
                          const Icon(
                            Icons.north_east_rounded,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final t = theme.textTheme;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: t.bodyMedium,
    h1: t.titleLarge,
    h2: t.titleMedium,
    h3: t.titleSmall,
    strong: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    listBullet: t.bodyMedium,
    blockSpacing: Space.xs,
    code: t.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: AppColors.info,
      backgroundColor: AppColors.surfaceHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: AppColors.border),
    ),
    tableHead: t.labelLarge,
    tableBody: t.bodySmall,
    tableBorder: TableBorder.all(color: AppColors.border),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );
}

class _Timestamp extends StatelessWidget {
  const _Timestamp(this.time);

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sameDay =
        now.year == time.year && now.month == time.month && now.day == time.day;
    return Text(
      DateFormat(sameDay ? 'h:mm a' : 'd MMM, h:mm a').format(time),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/surfaces.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.auto_awesome,
      'One assistant for your money',
      'Tell FLOWMINT what you need in plain words. It understands the request '
          'and prepares the right financial workflow.',
    ),
    (
      Icons.hub_outlined,
      'Six workflows, one place',
      'Split bills, draft quotations, shop, donate, track subscriptions and '
          'prepare refunds — all connected through the same assistant.',
    ),
    (
      Icons.verified_user_outlined,
      'Nothing moves without you',
      'The AI only prepares actions. You review every amount and recipient '
          'and approve each payment yourself.',
    ),
    (
      Icons.lock_outline_rounded,
      'Checkout secured by PayPal',
      'Payments are approved inside PayPal and verified by our secure '
          'backend. Your card details never touch FLOWMINT.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(sharedPreferencesProvider).setBool(onboardingSeenKey, true);
    if (mounted) context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: GlowBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Column(
              children: [
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    const BrandWordmark(markSize: 28),
                    const Spacer(),
                    if (!last)
                      TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final (icon, title, body) = _pages[i];
                      return FadeSlideIn(
                        key: ValueKey(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.brandSubtle,
                                borderRadius: BorderRadius.circular(Radii.lg),
                                border: Border.all(color: AppColors.brandMuted),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.brand.withValues(
                                      alpha: 0.22,
                                    ),
                                    blurRadius: 36,
                                  ),
                                ],
                              ),
                              child: Icon(
                                icon,
                                color: AppColors.brand,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: Space.xxl),
                            Text(title, style: t.displaySmall),
                            const SizedBox(height: Space.md),
                            Text(
                              body,
                              style: t.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _page ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? AppColors.brand
                              : AppColors.surfaceHighest,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xl),
                FilledButton(
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        ),
                  child: Text(last ? 'Get started' : 'Continue'),
                ),
                const SizedBox(height: Space.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

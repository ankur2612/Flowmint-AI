import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/payments/payment_models.dart';
import '../core/payments/payment_status_screen.dart';
import '../core/services/firebase_providers.dart';
import '../features/activity/activity_screen.dart';
import '../features/assistant/screens/assistant_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/onboarding_screen.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/auth/screens/sign_up_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/home/home_screen.dart';
import '../features/impact_giving/screens/campaign_detail_screen.dart';
import '../features/impact_giving/screens/campaigns_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/refund/refund_models.dart';
import '../features/refund/screens/refund_editor_screen.dart';
import '../features/refund/screens/refunds_screen.dart';
import '../features/shopping/screens/cart_screen.dart';
import '../features/shopping/screens/product_detail_screen.dart';
import '../features/shopping/screens/shop_screen.dart';
import '../features/smart_quotes/quote_models.dart';
import '../features/smart_quotes/screens/quote_editor_screen.dart';
import '../features/smart_quotes/screens/quote_preview_screen.dart';
import '../features/smart_quotes/screens/quotes_screen.dart';
import '../features/smart_split/screens/split_detail_screen.dart';
import '../features/smart_split/screens/split_editor_screen.dart';
import '../features/smart_split/screens/split_list_screen.dart';
import '../features/smart_split/split_models.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import 'app_shell.dart';

const onboardingSeenKey = 'onboarding_seen';

const _publicRoutes = {
  '/onboarding',
  '/sign-in',
  '/sign-up',
  '/forgot-password',
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final loc = state.matchedLocation;
      if (!auth.hasValue && !auth.hasError) {
        return loc == '/splash' ? null : '/splash';
      }
      final signedIn = auth.valueOrNull != null;
      if (!signedIn) {
        final onboarded =
            ref.read(sharedPreferencesProvider).getBool(onboardingSeenKey) ??
            false;
        if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
        return _publicRoutes.contains(loc) && loc != '/onboarding'
            ? null
            : '/sign-in';
      }
      if (loc == '/splash' || _publicRoutes.contains(loc)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assistant',
                builder: (_, s) => AssistantScreen(
                  initialPrompt: s.uri.queryParameters['prompt'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, _) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // SmartSplit
      GoRoute(path: '/split', builder: (_, _) => const SplitListScreen()),
      GoRoute(
        path: '/split/new',
        builder: (_, s) => SplitEditorScreen(draft: s.extra as SplitDraft?),
      ),
      GoRoute(
        path: '/split/:id',
        builder: (_, s) => SplitDetailScreen(id: s.pathParameters['id']!),
      ),

      // Refund Assistant
      GoRoute(path: '/refunds', builder: (_, s) => const RefundsScreen()),
      GoRoute(
        path: '/refunds/new',
        builder: (_, s) => RefundEditorScreen(
          draft: s.extra is RefundDraft ? s.extra as RefundDraft : null,
          linkedOrderId: s.extra is String ? s.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/refunds/:id',
        builder: (_, s) =>
            RefundEditorScreen(existingId: s.pathParameters['id']),
      ),

      // ImpactGiving
      GoRoute(
        path: '/giving',
        builder: (_, s) =>
            CampaignsScreen(cause: s.uri.queryParameters['cause']),
      ),
      GoRoute(
        path: '/giving/:id',
        builder: (_, s) => CampaignDetailScreen(
          id: s.pathParameters['id']!,
          initialAmountMinor: int.tryParse(
            s.uri.queryParameters['amount'] ?? '',
          ),
        ),
      ),

      // SmartQuotes
      GoRoute(path: '/quotes', builder: (_, _) => const QuotesScreen()),
      GoRoute(
        path: '/quotes/new',
        builder: (_, s) => QuoteEditorScreen(seed: s.extra as QuoteSeed?),
      ),
      GoRoute(
        path: '/quotes/:id',
        builder: (_, s) => QuotePreviewScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/quotes/:id/edit',
        builder: (_, s) =>
            QuoteEditorScreen(existingId: s.pathParameters['id']),
      ),

      // Subscription Intelligence
      GoRoute(
        path: '/subscriptions',
        builder: (_, _) => const SubscriptionsScreen(),
      ),

      // AI Shopping Agent
      GoRoute(
        path: '/shop',
        builder: (_, s) => ShopScreen(initialQuery: s.uri.queryParameters['q']),
      ),
      GoRoute(
        path: '/shop/product/:id',
        builder: (_, s) => ProductDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),

      // Verified PayPal records
      GoRoute(
        path: '/payments/:kind/:id',
        builder: (_, s) => PaymentStatusScreen(
          kind: PaymentKind.fromWire(s.pathParameters['kind']!),
          id: s.pathParameters['id']!,
        ),
      ),
    ],
  );
});

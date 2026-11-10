import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/surfaces.dart';
import '../activity/activity_screen.dart';
import '../profile/profile_repository.dart';
import 'home_overview.dart';

const _modules = [
  (Icons.call_split_rounded, 'SmartSplit', 'Split group bills', '/split'),
  (
    Icons.shopping_bag_outlined,
    'Shopping Agent',
    'Find & buy with AI',
    '/shop',
  ),
  (
    Icons.request_quote_outlined,
    'SmartQuotes',
    'Create client quotations',
    '/quotes',
  ),
  (
    Icons.autorenew_rounded,
    'Subscriptions',
    'Recurring spend',
    '/subscriptions',
  ),
  (Icons.undo_rounded, 'Refunds', 'Prepare requests', '/refunds'),
  (
    Icons.volunteer_activism_outlined,
    'ImpactGiving',
    'Donate to causes',
    '/giving',
  ),
];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider).valueOrNull;
    final overview = ref.watch(homeOverviewProvider);
    final name = profile?.firstName ?? '';

    var i = 0;
    Widget enter(Widget w) => FadeSlideIn(index: i++, child: w);

    return Scaffold(
      body: GlowBackdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              Space.xxl,
            ),
            children: [
              enter(
                Row(
                  children: [
                    const BrandMark(size: 30),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty
                                ? _greeting()
                                : '${_greeting()}, $name',
                            style: t.titleLarge,
                          ),
                          Text(
                            DateFormat('EEEE, d MMMM').format(DateTime.now()),
                            style: t.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/profile'),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.surfaceHighest,
                        child: Text(
                          profile?.initials ?? '',
                          style: t.titleSmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              enter(
                overview.when(
                  loading: () => const HeroSurface(
                    child: SizedBox(height: 180, child: LoadingView()),
                  ),
                  error: (e, _) =>
                      HeroSurface(child: ErrorState(message: friendlyError(e))),
                  data: (o) => _OverviewCard(overview: o),
                ),
              ),
              const SizedBox(height: Space.md),
              enter(_AskCard(onTap: () => context.go('/assistant'))),
              const SizedBox(height: Space.lg),
              enter(const SectionHeader('Quick actions')),
              enter(
                Row(
                  children: [
                    _QuickAction(
                      Icons.call_split_rounded,
                      'Split bill',
                      () => context.push('/split/new'),
                    ),
                    _QuickAction(
                      Icons.description_outlined,
                      'New quote',
                      () => context.push('/quotes/new'),
                    ),
                    _QuickAction(
                      Icons.search_rounded,
                      'Shop',
                      () => context.push('/shop'),
                    ),
                    _QuickAction(
                      Icons.document_scanner_outlined,
                      'Scan receipt',
                      () => context.push('/refunds/new'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              enter(const SectionHeader('Explore FLOWMINT')),
              enter(
                Column(
                  children: [
                    for (var r = 0; r < _modules.length; r += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _ModuleCard(module: _modules[r])),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: r + 1 < _modules.length
                                    ? _ModuleCard(module: _modules[r + 1])
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (overview.valueOrNull != null) ...[
                const SizedBox(height: Space.lg),
                enter(_SubscriptionOverview(overview: overview.value!)),
                const SizedBox(height: Space.lg),
                SectionHeader(
                  'Recent activity',
                  actionLabel: overview.value!.recent.isEmpty
                      ? null
                      : 'See all',
                  onAction: () => context.go('/activity'),
                ),
                if (overview.value!.recent.isEmpty)
                  const AppCard(
                    child: EmptyState(
                      compact: true,
                      icon: Icons.receipt_long_outlined,
                      title: 'No activity yet',
                      message:
                          'Your payments, splits and quotations will show up here.',
                    ),
                  )
                else
                  for (final e in overview.value!.recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: ActivityTile(entry: e),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.overview});

  final HomeOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = overview;
    return LightPanel(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.brandDeep,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.xs),
              Text(
                'FINANCIAL OVERVIEW',
                style: t.labelSmall?.copyWith(color: AppColors.brandDeep),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            'PAID THROUGH PAYPAL · ${DateFormat('MMMM').format(DateTime.now()).toUpperCase()}',
            style: t.labelSmall?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: Space.xs),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: o.paidThisMonthMinor.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              Money.format(v.round(), currency: o.paidCurrency, compact: true),
              style: t.displaySmall?.copyWith(
                fontSize: 40,
                letterSpacing: -1.4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            o.paymentsThisMonth == 0
                ? 'No verified payments this month'
                : '${o.paymentsThisMonth} verified payment${o.paymentsThisMonth == 1 ? '' : 's'}',
            style: t.bodySmall?.copyWith(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.md),
          Row(
            children: [
              _Figure(
                'Subscriptions / mo',
                Money.format(o.subscriptions.monthlyMinor, compact: true),
              ),
              _Figure(
                'Owed to you',
                Money.format(o.owedToYouMinor, compact: true),
              ),
              _Figure(
                'Awaiting from clients',
                Money.format(o.awaitingFromClientsMinor, compact: true),
              ),
            ],
          ),
          if (o.isEmpty) ...[
            const SizedBox(height: Space.md),
            Text(
              'Your overview fills in as you split bills, track subscriptions, send quotations and pay with PayPal.',
              style: t.bodySmall?.copyWith(color: AppColors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            label,
            style: t.bodySmall?.copyWith(
              color: AppColors.inkSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AskCard extends StatelessWidget {
  const _AskCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      color: AppColors.brandSubtle,
      borderColor: AppColors.brandMuted,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.brand),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask FLOWMINT AI', style: t.titleSmall),
                Text(
                  '"Split dinner ₹2,400 between 4 of us"',
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: AppColors.brand),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, color: AppColors.textPrimary, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionOverview extends StatelessWidget {
  const _SubscriptionOverview({required this.overview});

  final HomeOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = overview.subscriptions;
    final next = s.upcoming.firstOrNull;
    return AppCard(
      onTap: () => context.push('/subscriptions'),
      child: Row(
        children: [
          const IconTile(Icons.autorenew_rounded),
          const SizedBox(width: Space.sm),
          Expanded(
            child: s.activeCount == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Subscriptions', style: t.titleSmall),
                      Text(
                        'Add the services you pay for to track renewals',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Money.format(s.monthlyMinor)} / month · ${s.activeCount} active',
                        style: t.titleSmall,
                      ),
                      Text(
                        next == null
                            ? 'No renewals in the next 7 days'
                            : 'Next: ${next.subscription.name} on ${DateFormat('d MMM').format(next.date)}',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final (IconData, String, String, String) module;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, title, subtitle, route) = module;
    return AppCard(
      onTap: () => context.push(route),
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          IconTile(icon, size: 36),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: t.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

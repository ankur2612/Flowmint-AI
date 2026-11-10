import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_providers.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../assistant/assistant_controller.dart';
import '../auth/auth_repository.dart';
import 'profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<String?> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    String? helper,
    String? prefix,
    String? Function(String)? validate,
  }) {
    final controller = TextEditingController(text: initial);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              helperText: helper,
              prefixText: prefix,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                final e = validate?.call(v);
                if (e != null) {
                  setState(() => error = e);
                } else {
                  Navigator.pop(c, v);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> fields,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).update(fields);
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _toggleNotification(
    BuildContext context,
    WidgetRef ref,
    String field,
    bool value,
  ) async {
    if (value) {
      final uid = ref.read(uidProvider);
      if (uid != null) {
        final granted = await ref
            .read(notificationServiceProvider)
            .register(uid);
        if (!granted && context.mounted) {
          showMessage(
            context,
            'Allow notifications for FLOWMINT in Android settings to receive alerts.',
          );
        }
      }
    }
    if (context.mounted) await _update(context, ref, {field: value});
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final uid = ref.read(uidProvider);
    if (uid != null) {
      await ref.read(notificationServiceProvider).unregister(uid);
    }
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(profileProvider);
    final p = profile.valueOrNull;
    final usesPassword =
        user?.providerData.any((i) => i.providerId == 'password') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.isLoading && p == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, Space.xs, 0, Space.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.brandSubtle,
                        child: Text(
                          p?.initials ?? '',
                          style: t.titleLarge?.copyWith(color: AppColors.brand),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (p?.displayName.isNotEmpty ?? false)
                                  ? p!.displayName
                                  : 'Your profile',
                              style: t.titleLarge,
                            ),
                            Text(
                              user?.email ?? '',
                              style: t.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const _Group('Profile'),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Display name'),
                  subtitle: Text(
                    (p?.displayName.isNotEmpty ?? false)
                        ? p!.displayName
                        : 'Not set',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final v = await _editText(
                      context,
                      title: 'Display name',
                      initial: p?.displayName ?? '',
                      validate: (v) => v.length < 2 ? 'Enter your name' : null,
                    );
                    if (v == null || !context.mounted) return;
                    await _update(context, ref, {'displayName': v});
                    await user?.updateDisplayName(v);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('PayPal.me username'),
                  subtitle: Text(
                    p?.paypalMeUsername == null
                        ? 'Add it to include a PayPal link in split requests'
                        : 'paypal.me/${p!.paypalMeUsername}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final v = await _editText(
                      context,
                      title: 'PayPal.me username',
                      initial: p?.paypalMeUsername ?? '',
                      prefix: 'paypal.me/',
                      helper: 'Leave empty to remove',
                      validate: (v) =>
                          v.isEmpty ||
                              RegExp(r'^[A-Za-z0-9]{1,20}$').hasMatch(v)
                          ? null
                          : 'Letters and numbers only (max 20)',
                    );
                    if (v == null || !context.mounted) return;
                    await _update(context, ref, {
                      'paypalMeUsername': v.isEmpty ? null : v,
                    });
                  },
                ),
                const _Group('Payment methods'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: AppCard(
                    child: Row(
                      children: [
                        const IconTile(Icons.account_balance_wallet_outlined),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('PayPal Checkout', style: t.titleSmall),
                                  if (AppConstants.isSandbox) ...[
                                    const SizedBox(width: Space.xs),
                                    const StatusBadge(
                                      'Sandbox',
                                      tone: Tone.warning,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'You sign in and approve each payment inside PayPal. FLOWMINT never stores card or bank details.',
                                style: t.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const _Group('Notifications'),
                SwitchListTile(
                  secondary: const Icon(Icons.payments_outlined),
                  title: const Text('Payment updates'),
                  subtitle: const Text(
                    'When PayPal confirms or declines a payment',
                  ),
                  value: p?.notifyPayments ?? true,
                  onChanged: (v) =>
                      _toggleNotification(context, ref, 'notifyPayments', v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.event_repeat_outlined),
                  title: const Text('Renewal reminders'),
                  subtitle: const Text('3 days before a subscription renews'),
                  value: p?.notifyRenewals ?? true,
                  onChanged: (v) =>
                      _toggleNotification(context, ref, 'notifyRenewals', v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_none_rounded),
                  title: const Text('Refund updates'),
                  subtitle: const Text('When a PayPal refund is completed'),
                  value: p?.notifyActivity ?? true,
                  onChanged: (v) =>
                      _toggleNotification(context, ref, 'notifyActivity', v),
                ),
                const _Group('Security'),
                if (usesPassword)
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password'),
                    subtitle: const Text(
                      'We will email you a secure reset link',
                    ),
                    onTap: () async {
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .sendPasswordReset(user!.email!);
                        if (context.mounted) {
                          showMessage(
                            context,
                            'Reset link sent to ${user.email}',
                          );
                        }
                      } on AuthException catch (e) {
                        if (context.mounted) showMessage(context, e.message);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Payment approval'),
                  subtitle: const Text(
                    'Every payment requires your confirmation in FLOWMINT and approval in PayPal',
                  ),
                ),
                const _Group('Privacy'),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear assistant history'),
                  subtitle: const Text(
                    'Delete your stored conversation with FLOWMINT AI',
                  ),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Clear assistant history?'),
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
                      await ref
                          .read(assistantControllerProvider.notifier)
                          .clear();
                      if (context.mounted) {
                        showMessage(context, 'Assistant history cleared');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showMessage(context, friendlyError(e));
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('How your data is used'),
                  subtitle: const Text(
                    'Your records are private to your account. Messages and documents you send to the assistant are processed by Google Gemini to answer you.',
                  ),
                ),
                if (kDebugMode &&
                    ref.watch(appCheckDebugTokenProvider) != null) ...[
                  const _Group('Developer'),
                  ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('App Check debug token'),
                    subtitle: Text(
                      'Debug build only. Register it in Firebase console → '
                      'App Check → Apps → Manage debug tokens to enable AI.\n'
                      '${ref.watch(appCheckDebugTokenProvider)}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.copy_rounded),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: ref.read(appCheckDebugTokenProvider)!,
                        ),
                      );
                      if (context.mounted) showMessage(context, 'Token copied');
                    },
                  ),
                ],
                const _Group('Account'),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  onTap: () => _signOut(context, ref),
                ),
              ],
            ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xl,
        Space.gutter,
        Space.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

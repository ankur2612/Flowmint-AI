import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/inputs.dart';
import '../auth_repository.dart';
import '../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      title: 'Reset password',
      subtitle: "Enter your account email and we'll send you a reset link.",
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _sent
              ? Container(
                  key: const ValueKey('sent'),
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: AppColors.brandSubtle,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: AppColors.brandMuted),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          'If an account exists for ${_email.text.trim()}, '
                          'a reset link is on its way.',
                        ),
                      ),
                    ],
                  ),
                )
              : Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: validateEmail,
                      ),
                      const SizedBox(height: Space.xl),
                      AuthErrorBanner(_error),
                      LoadingButton(
                        label: 'Send reset link',
                        loading: _busy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

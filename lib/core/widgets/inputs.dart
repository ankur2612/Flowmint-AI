import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../utils/money.dart';

/// Currency amount input with validation. Value is read with
/// [Money.parseToMinor] on the controller's text.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.label = 'Amount',
    this.allowZero = false,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String currency;
  final String label;
  final bool allowZero;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${Money.symbol(currency)} ',
      ),
      onChanged: onChanged,
      validator: (v) {
        final minor = Money.parseToMinor(v ?? '');
        if (minor == null) return 'Enter a valid amount';
        if (!allowZero && minor == 0) return 'Amount must be greater than zero';
        return null;
      },
    );
  }
}

/// Filled button that shows progress and blocks repeat taps while [loading].
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: loading
            ? const SizedBox(
                key: ValueKey('progress'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.textSecondary,
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Disposes text controllers of a removed form row after the current frame,
/// once the fields that used them have been unmounted.
void disposeLater(VoidCallback dispose) =>
    WidgetsBinding.instance.addPostFrameCallback((_) => dispose());

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// Fades and lifts its child into place, staggered by [index], for calm
/// entrance choreography on dashboards and lists.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 0.08).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + (index * 60).clamp(0, 360)),
      curve: Interval(delay, 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// Soft ambient mint light behind a screen's content. Purely decorative and
/// cheap: two blurred radial gradients painted once.
class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -180,
          left: -140,
          child: _Orb(size: 420, alpha: 0.16 * intensity),
        ),
        Positioned(
          top: 120,
          right: -200,
          child: _Orb(size: 360, alpha: 0.07 * intensity),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.brand.withValues(alpha: alpha),
              AppColors.brand.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single most important surface on a screen (e.g. the financial
/// overview): a graphite card with a faint mint sheen and hairline border.
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.lg + 4);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E3A6E), AppColors.surface, Color(0xFF09213D)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned(
                top: -60,
                right: -40,
                child: IgnorePointer(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.brand.withValues(alpha: 0.14),
                          AppColors.brand.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// White content panel inside the navy shell. Descendants that read colours
/// from the theme (text, icons, DetailRow) switch to navy ink automatically.
class LightPanel extends StatelessWidget {
  const LightPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.onTap,
    this.borderColor = AppColors.paperBorder,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.paper,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.inkSecondary,
        outlineVariant: AppColors.paperBorder,
        surfaceContainerHighest: AppColors.paperAlt,
        primary: AppColors.brandDeep,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      iconTheme: const IconThemeData(color: AppColors.inkSecondary),
      dividerTheme: const DividerThemeData(
        color: AppColors.paperBorder,
        thickness: 1,
        space: 1,
      ),
    );
    final radius = BorderRadius.circular(Radii.lg);
    return Theme(
      data: theme,
      child: Material(
        color: AppColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: borderColor,
            width: borderColor == AppColors.paperBorder ? 1 : 1.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: AppColors.ink),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Central colour tokens for FLOWMINT: deep navy surfaces with
/// PayPal-inspired blue for actions. Screens must use these tokens (or the
/// derived ColorScheme) rather than literal colours.
abstract final class AppColors {
  static const background = Color(0xFF071B33);
  static const surface = Color(0xFF0B2545);
  static const surfaceRaised = Color(0xFF102F50);
  static const surfaceHighest = Color(0xFF153653);
  static const border = Color(0xFF1C3D61);
  static const borderStrong = Color(0xFF2A5078);

  static const brand = Color(0xFF009CDE);
  static const brandDeep = Color(0xFF0070E0);
  static const brandMuted = Color(0xFF1F4E86);
  static const brandSubtle = Color(0xFF0E2E57);
  static const onBrand = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA9BBCD);
  static const textTertiary = Color(0xFF7189A3);

  // Light content surfaces used inside the navy shell.
  static const paper = Color(0xFFFFFFFF);
  static const paperAlt = Color(0xFFF4F7FA);
  static const paperBorder = Color(0xFFD9E2EC);
  static const ink = Color(0xFF142B45);
  static const inkSecondary = Color(0xFF5A6E82);

  static const success = Color(0xFF2FBF71);
  static const warning = Color(0xFFE6A23C);
  static const danger = Color(0xFFE25C5C);
  static const info = Color(0xFF7FC4FF);
  static const neutral = Color(0xFF8DA2B8);
}

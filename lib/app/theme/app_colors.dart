import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary colors (Indigo)
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);

  // Secondary colors (Violet)
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color secondaryLight = Color(0xFFA78BFA);
  static const Color secondaryDark = Color(0xFF7C3AED);

  // Tertiary colors (Cyan)
  static const Color tertiary = Color(0xFF06B6D4);
  static const Color tertiaryLight = Color(0xFF22D3EE);
  static const Color tertiaryDark = Color(0xFF0891B2);

  // Neutral colors - Light
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightOnSurface = Color(0xFF1E293B);
  static const Color lightOnSurfaceVariant = Color(0xFF64748B);
  static const Color lightOutline = Color(0xFFCBD5E1);
  static const Color lightOutlineVariant = Color(0xFFE2E8F0);

  // Neutral colors - Dark (Catppuccin Mocha inspired)
  static const Color darkBackground = Color(0xFF11111B);
  static const Color darkSurface = Color(0xFF1E1E2E);
  static const Color darkSurfaceVariant = Color(0xFF313244);
  static const Color darkOnSurface = Color(0xFFCDD6F4);
  static const Color darkOnSurfaceVariant = Color(0xFFA6ADC8);
  static const Color darkOutline = Color(0xFF45475A);
  static const Color darkOutlineVariant = Color(0xFF313244);

  // Semantic colors
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFCA5A5);
  static const Color errorDark = Color(0xFFDC2626);

  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFF86EFAC);
  static const Color successDark = Color(0xFF16A34A);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFCD34D);
  static const Color warningDark = Color(0xFFD97706);

  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFF93C5FD);
  static const Color infoDark = Color(0xFF2563EB);
}

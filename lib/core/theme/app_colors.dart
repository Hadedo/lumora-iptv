import 'package:flutter/material.dart';

/// مجموعة ألوان كاملة لمظهر واحد (داكن أو فاتح).
class AppPalette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
}

/// ألوان هوية لُمورا.
class AppColors {
  AppColors._();

  // ألوان الهوية (ثابتة في المظهرين)
  static const Color primary = Color(0xFF7C5CFF);
  static const Color primaryDark = Color(0xFF5B3DE0);
  static const Color secondary = Color(0xFF2EE6D6);
  static const Color live = Color(0xFFFF4D5E);

  // ألوان الحالة
  static const Color success = Color(0xFF2ED573);
  static const Color warning = Color(0xFFFFB84D);
  static const Color error = Color(0xFFFF4D5E);

  // التدرجات
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x337C5CFF), Color(0x00000000)],
  );

  static const LinearGradient playerShade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xCC000000), Color(0x00000000), Color(0xCC000000)],
    stops: [0.0, 0.5, 1.0],
  );

  // المظهر الداكن (الافتراضي)
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0D14),
    surface: Color(0xFF151926),
    surfaceHigh: Color(0xFF1E2335),
    border: Color(0xFF2A3047),
    textPrimary: Color(0xFFF2F4FA),
    textSecondary: Color(0xFFA3A9BD),
    textMuted: Color(0xFF6B7187),
  );

  // المظهر الفاتح
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEF0F7),
    border: Color(0xFFDDE0EC),
    textPrimary: Color(0xFF12141C),
    textSecondary: Color(0xFF555B70),
    textMuted: Color(0xFF8A90A5),
  );
}

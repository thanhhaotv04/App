import 'package:flutter/material.dart';

class AppColors {
  const AppColors({
    required this.bg,
    required this.bg2,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.good,
    required this.warning,
  });

  final Color bg;
  final Color bg2;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accent2;
  final Color good;
  final Color warning;

  static AppColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static const light = AppColors(
    bg: Color(0xFFF8F3E7),
    bg2: Color(0xFFF3E9D7),
    panel: Color(0xFFFFFBF3),
    panel2: Color(0xFFFCF2E8),
    line: Color(0xFFE3D6BF),
    text: Color(0xFF29251F),
    muted: Color(0xFF7C7163),
    accent: Color(0xFFCB7B2B),
    accent2: Color(0xFFA95F21),
    good: Color(0xFF86C95A),
    warning: Color(0xFFF1D46D),
  );

  static const dark = AppColors(
    bg: Color(0xFF272822),
    bg2: Color(0xFF1F211B),
    panel: Color(0xFF2F3028),
    panel2: Color(0xFF292A23),
    line: Color(0xFF44463B),
    text: Color(0xFFF8F8F2),
    muted: Color(0xFFC6C4A4),
    accent: Color(0xFFE6DB74),
    accent2: Color(0xFFFD971F),
    good: Color(0xFFA6E22E),
    warning: Color(0xFFF0DD78),
  );
}

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
    bg: Color(0xFFF4EFE2),
    bg2: Color(0xFFEFE5D2),
    panel: Color(0xFFFFF9F0),
    panel2: Color(0xFFF8F1E4),
    line: Color(0xFFE3D7C3),
    text: Color(0xFF2E2922),
    muted: Color(0xFF786C5D),
    accent: Color(0xFFC47731),
    accent2: Color(0xFFAD6829),
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

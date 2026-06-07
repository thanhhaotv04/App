import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

  static void toggleTheme() {
    themeMode.value = themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  static ThemeData light() {
    const tokens = AppColors.light;
    final seed = tokens.accent;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      textTheme: _textTheme(tokens),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: const Color(0xFFF1E5D5),
        foregroundColor: tokens.text,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF5E4D6),
        indicatorColor: const Color(0xFFFFD2B2),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(color: tokens.muted, fontSize: 12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: _inputTheme(tokens),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: const Color(0xFF1E1B16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const tokens = AppColors.dark;
    final seed = tokens.accent;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      textTheme: _textTheme(tokens),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: tokens.panel,
        foregroundColor: tokens.text,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.panel2,
        indicatorColor: tokens.line,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(color: tokens.muted, fontSize: 12),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: _inputTheme(tokens),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: const Color(0xFF1E1B16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }

  static TextTheme _textTheme(AppColors tokens) {
    return TextTheme(
      headlineMedium: TextStyle(color: tokens.text, fontWeight: FontWeight.w800),
      titleLarge: TextStyle(color: tokens.text, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(color: tokens.text, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: tokens.text, height: 1.5),
      bodyMedium: TextStyle(color: tokens.text, height: 1.45),
      bodySmall: TextStyle(color: tokens.muted, height: 1.4),
      labelLarge: TextStyle(color: tokens.text, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(color: tokens.muted, fontWeight: FontWeight.w600),
    );
  }

  static InputDecorationTheme _inputTheme(AppColors tokens) {
    return InputDecorationTheme(
      filled: true,
      fillColor: tokens.panel2,
      labelStyle: TextStyle(color: tokens.muted),
      hintStyle: TextStyle(color: tokens.muted.withValues(alpha: 0.75)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: tokens.line)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: tokens.accent, width: 2)),
    );
  }
}

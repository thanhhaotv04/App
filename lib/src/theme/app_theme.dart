import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.light,
  );

  static void toggleTheme() {
    themeMode.value = themeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  static ThemeData light() {
    const tokens = AppColors.light;
    final seed = tokens.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: tokens.panel,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      textTheme: _textTheme(tokens),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: const Color(0xFFF1E2CE),
        foregroundColor: tokens.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 84,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 88,
        elevation: 0,
        backgroundColor: const Color(0xFFF7E2D1),
        indicatorColor: const Color(0xFFFFCDA9),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: tokens.text,
            size: states.contains(WidgetState.selected) ? 30 : 28,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: tokens.muted,
            fontSize: 13,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: tokens.line),
        ),
      ),
      inputDecorationTheme: _inputTheme(tokens),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: const Color(0xFF1E1B16),
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.accent2,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          side: BorderSide(color: tokens.muted),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent2,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      dividerColor: tokens.line,
    );
  }

  static ThemeData dark() {
    const tokens = AppColors.dark;
    final seed = tokens.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
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
        scrolledUnderElevation: 0,
        toolbarHeight: 84,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 88,
        backgroundColor: tokens.panel2,
        indicatorColor: tokens.line,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.all(
          IconThemeData(color: tokens.text, size: 29),
        ),
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
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.accent,
          minimumSize: const Size(48, 52),
          side: BorderSide(color: tokens.muted),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        ),
      ),
    );
  }

  static TextTheme _textTheme(AppColors tokens) {
    return TextTheme(
      headlineLarge: TextStyle(
        color: tokens.text,
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w900,
      ),
      headlineMedium: TextStyle(
        color: tokens.text,
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w900,
      ),
      titleLarge: TextStyle(
        color: tokens.text,
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w900,
      ),
      titleMedium: TextStyle(
        color: tokens.text,
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: TextStyle(color: tokens.text, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(color: tokens.text, fontSize: 15, height: 1.45),
      bodySmall: TextStyle(color: tokens.muted, fontSize: 13, height: 1.4),
      labelLarge: TextStyle(
        color: tokens.text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
      labelMedium: TextStyle(color: tokens.muted, fontWeight: FontWeight.w600),
    );
  }

  static InputDecorationTheme _inputTheme(AppColors tokens) {
    return InputDecorationTheme(
      filled: true,
      fillColor: tokens.panel2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: TextStyle(color: tokens.muted),
      hintStyle: TextStyle(color: tokens.muted.withValues(alpha: 0.75)),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.line),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: tokens.accent, width: 2),
      ),
    );
  }
}

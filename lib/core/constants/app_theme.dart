import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF4B44CC);
  static const accent = Color(0xFF00D2A0);

  // Dark theme
  static const darkBg = Color(0xFF0F0F14);
  static const darkSurface = Color(0xFF1A1A24);
  static const darkCard = Color(0xFF22222F);
  static const darkBorder = Color(0xFF2E2E3E);
  static const darkText = Color(0xFFEEEEF5);
  static const darkSubtext = Color(0xFF8888AA);

  // Light theme
  static const lightBg = Color(0xFFF5F5FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF0F0F8);
  static const lightBorder = Color(0xFFDDDDEE);
  static const lightText = Color(0xFF1A1A2E);
  static const lightSubtext = Color(0xFF6666888);

  // Status
  static const success = Color(0xFF00D2A0);
  static const warning = Color(0xFFFFB347);
  static const error = Color(0xFFFF5C6A);
  static const info = Color(0xFF4FC3F7);

  // Networks
  static const globe = Color(0xFF0070C0);
  static const smart = Color(0xFFCC0000);
  static const dito = Color(0xFF00AA44);
  static const others = Color(0xFF888888);
}

class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.darkSurface,
        error: AppColors.error,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.darkText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primary.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.darkSubtext, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.darkSubtext),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkCard,
        selectedColor: AppColors.primary.withOpacity(0.3),
        side: const BorderSide(color: AppColors.darkBorder),
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.darkText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.darkText, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: AppColors.darkText, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        headlineSmall: TextStyle(color: AppColors.darkText, fontSize: 18, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: AppColors.darkText, fontSize: 16, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: AppColors.darkText, fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: AppColors.darkSubtext, fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: AppColors.darkText, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.darkText, fontSize: 14),
        bodySmall: TextStyle(color: AppColors.darkSubtext, fontSize: 12),
        labelLarge: TextStyle(color: AppColors.darkText, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: AppColors.darkSubtext, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.lightSurface,
        error: AppColors.error,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.lightText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.lightText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: Color(0xFF9999AA), fontSize: 14),
        labelStyle: const TextStyle(color: Color(0xFF666677)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightCard,
        selectedColor: AppColors.primary.withOpacity(0.15),
        side: const BorderSide(color: AppColors.lightBorder),
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.lightText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.lightText, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: AppColors.lightText, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        headlineSmall: TextStyle(color: AppColors.lightText, fontSize: 18, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: AppColors.lightText, fontSize: 16, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: AppColors.lightText, fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: Color(0xFF666688), fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: AppColors.lightText, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.lightText, fontSize: 14),
        bodySmall: TextStyle(color: Color(0xFF666688), fontSize: 12),
        labelLarge: TextStyle(color: AppColors.lightText, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: Color(0xFF666688), fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
    );
  }
}
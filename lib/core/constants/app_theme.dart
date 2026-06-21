import 'package:flutter/material.dart';

class AppColors {
  // Brand — dark mode uses green, light mode uses deeper green
  static const primary = Color(0xFF00D2A0);
  static const primaryDark = Color(0xFF00B88C);
  static const accent = Color(0xFF00D2A0);

  // Dark theme
  static const darkBg = Color(0xFF0A0F0D);
  static const darkSurface = Color(0xFF121916);
  static const darkCard = Color(0xFF1A2420);
  static const darkBorder = Color(0xFF253030);
  static const darkText = Color(0xFFE8F0EC);
  static const darkSubtext = Color(0xFF7A9088);

  // Light theme
  static const lightBg = Color(0xFFF6F8F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFEEF2F0);
  static const lightBorder = Color(0xFFD8DDD9);
  static const lightText = Color(0xFF1A2420);
  static const lightSubtext = Color(0xFF667770);

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
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: AppColors.darkSubtext, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.darkSubtext),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.darkBg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
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
        primary: Color(0xFF2D6A4F),
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
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: Color(0xFF889990), fontSize: 14),
        labelStyle: const TextStyle(color: Color(0xFF667770)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2D6A4F),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2D6A4F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightCard,
        selectedColor: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
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
        titleSmall: TextStyle(color: Color(0xFF667770), fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: AppColors.lightText, fontSize: 15),
        bodyMedium: TextStyle(color: AppColors.lightText, fontSize: 14),
        bodySmall: TextStyle(color: Color(0xFF667770), fontSize: 12),
        labelLarge: TextStyle(color: AppColors.lightText, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: Color(0xFF667770), fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
    );
  }
}

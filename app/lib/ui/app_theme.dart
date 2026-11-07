import 'package:flutter/material.dart';

abstract final class AppColors {
  static const forest = Color(0xFF123C32);
  static const forestLight = Color(0xFF1C5445);
  static const amber = Color(0xFFF6B73C);
  static const canvas = Color(0xFFF5F5F0);
  static const ink = Color(0xFF17221E);
  static const muted = Color(0xFF65736D);
  static const line = Color(0xFFE2E6E1);

  // Extended small-business palette (target look, deeper accents)
  static const terracotta = Color(0xFFB85C38);
  static const sky = Color(0xFF2E6F95);
  static const sage = Color(0xFF7FA650);
  static const plum = Color(0xFF6B4F7A);
  static const slate = Color(0xFF4A5568);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFB26A00);
  static const danger = Color(0xFFB3261E);
  static const info = Color(0xFF1565C0);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.forest,
    brightness: Brightness.light,
    surface: Colors.white,
  ).copyWith(
    secondary: AppColors.amber,
    onSecondary: AppColors.ink,
    tertiary: AppColors.terracotta,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.forest,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFFFE9BE),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Universal text-scale clamp for cards, buttons and rows.
///
/// Flutter's default text scaler lets the system font grow unbounded; on
/// large-scale phones that crushed rows into a vertical ribbon (the
/// "Business tab text reading down" bug, and the same in "Parcels in
/// flight", KPI tiles, plan cards, etc.). We clamp it everywhere:
///  * min 1.0x — never shrink below the system size (accessibility).
///  * max 1.30x — never grow past 1.3x so a 14sp body can't become a
///    26sp ribbon in a 60%-width slot.
double clampTextScale(BuildContext context, double value) {
  final tsf = MediaQuery.textScalerOf(context).scale(1);
  return value.clamp(1.0, 1.3 * tsf);
}

/// Backwards-compat: base heading size scaled by the clamped system factor.
double scaleText(BuildContext context, double baseSize) =>
    baseSize * clampTextScale(context, 1);

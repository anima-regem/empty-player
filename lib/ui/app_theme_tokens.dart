import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemeTokens {
  static const Color scaffold = Color(0xFF070A0D);
  static const Color surface = Color(0xFF11161D);
  static const Color surfaceAlt = Color(0xFF1A2330);
  static const Color accent = Color(0xFF7AE6C5);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9AA7B8);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = GoogleFonts.latoTextTheme(base.textTheme).apply(
    bodyColor: AppThemeTokens.textPrimary,
    displayColor: AppThemeTokens.textPrimary,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppThemeTokens.scaffold,
    textTheme: textTheme,
    colorScheme: base.colorScheme.copyWith(
      surface: AppThemeTokens.surface,
      primary: AppThemeTokens.accent,
      onPrimary: Colors.black,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppThemeTokens.scaffold,
      elevation: 0,
      foregroundColor: AppThemeTokens.textPrimary,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppThemeTokens.surface,
      textStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppThemeTokens.surfaceAlt,
      contentTextStyle: textTheme.bodyMedium,
    ),
  );
}

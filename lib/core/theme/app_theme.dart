// lib/core/theme/app_theme.dart
//
// Green-forward theme, built with dark mode as a first-class citizen
// (not an afterthought bolted onto a light theme).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const seed = Color(0xFF2FA36A);

  // Light
  static const lightBg = Color(0xFFF7F8F7);
  static const lightSurface = Colors.white;

  // Dark
  static const darkBg = Color(0xFF090B0A);
  static const darkSurface = Color(0xFF111614);
  static const darkSurface2 = Color(0xFF181F1B);
  static const darkBorder = Color(0xFF29322D);

  static const success = Color(0xFF2FA36A);
  static const warning = Color(0xFFE9A63C);
  static const danger = Color(0xFFE15A52);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
    );
    return _base(scheme, AppColors.lightBg, AppColors.lightSurface);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: AppColors.success,
      secondary: const Color(0xFF58B982),

      surface: AppColors.darkSurface,

      onSurface: Colors.white,
      onPrimary: Colors.white,

      outline: AppColors.darkBorder,
      outlineVariant: const Color(0xFF1F2723),
    );

    return _base(
      scheme,
      AppColors.darkBg,
      AppColors.darkSurface,
    );
  }

  static ThemeData _base(ColorScheme scheme, Color bg, Color surface) {
      final textTheme = GoogleFonts.interTextTheme().apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      canvasColor: AppColors.darkBg,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: AppColors.darkBorder,
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface2,

        labelStyle: const TextStyle(
          color: Color(0xFF9FA8A3),
        ),

        hintStyle: const TextStyle(
          color: Color(0xFF78817C),
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.darkBorder,
          ),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.success,
            width: 1.5,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4)),
    );
  }
}

// Status → color mapping used across the app (loan status chips, stage trackers)
class StatusColors {
  static Color forLoanStatus(String status, ColorScheme scheme) {
    switch (status) {
      case 'submitted':
      case 'in_review':
        return const Color(0xFFE9A63C); // amber — in motion
      case 'approved':
        return const Color(0xFF2FA36A); // green — good
      case 'disbursed':
        return scheme.primary; // brand green — done
      case 'rejected':
        return const Color(0xFFD9534F); // red
      case 'returned':
        return const Color(0xFF6C7A89); // grey — needs attention
      default:
        return scheme.outline;
    }
  }
}

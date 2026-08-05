import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.green,
      onPrimary: Colors.white,
      primaryContainer: AppColors.greenSoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.terracotta,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.terracottaSoft,
      onSecondaryContainer: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      outline: AppColors.border,
      error: AppColors.error,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            displaySmall: const TextStyle(
              fontSize: 42,
              height: 1.02,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.6,
            ),
            headlineMedium: const TextStyle(
              fontSize: 28,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.8,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: const TextStyle(fontSize: 16, height: 1.45),
            bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
            labelLarge: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.greenSoft,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? AppColors.green : AppColors.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),
    );
  }
}

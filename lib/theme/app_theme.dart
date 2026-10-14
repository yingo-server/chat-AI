import 'package:flutter/material.dart';

import '../utils/error_code.dart';

class AppTheme {
  static ThemeData light(Color? seed) {
    try {
      final scheme = ColorScheme.fromSeed(
        seedColor: seed ?? const Color(0xFF7B61FF),
        brightness: Brightness.light,
      );
      return _build(scheme);
    } catch (e, st) {
      throw AppError(Ec.th00.code, Ec.th00.message, cause: e, stack: st);
    }
  }

  static ThemeData dark(Color? seed) {
    try {
      final scheme = ColorScheme.fromSeed(
        seedColor: seed ?? const Color(0xFF7B61FF),
        brightness: Brightness.dark,
      );
      return _build(scheme);
    } catch (e, st) {
      throw AppError(Ec.th00.code, Ec.th00.message, cause: e, stack: st);
    }
  }

  static ThemeData _build(ColorScheme scheme) {
    try {
      final base = ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      );
      return base.copyWith(
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: scheme.onSurface,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: scheme.surfaceContainerHigh,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    } catch (e, st) {
      throw AppError(Ec.th00.code, Ec.th00.message, cause: e, stack: st);
    }
  }
}
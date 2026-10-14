import 'package:flutter/material.dart';

/// M3 主题 — 根据 seed 颜色构建
class AppTheme {
  static ThemeData light(Color? seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed ?? const Color(0xFF7B61FF),
      brightness: Brightness.light,
    );
    return _build(scheme);
  }

  static ThemeData dark(Color? seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed ?? const Color(0xFF7B61FF),
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  }
}
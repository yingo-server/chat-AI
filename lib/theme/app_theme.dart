import 'package:flutter/material.dart';

import 'spacing.dart';

/// M3 主题 — 单一 seed 派生 + 组件级规范补齐
/// 参考 Material 3 规范:形状刻度(4/8/12/16/28)、色彩角色、状态层、浮层规范
class AppTheme {
  static const _fallbackSeed = Color(0xFF7B61FF);

  static ThemeData light(Color? seed) =>
      _build(ColorScheme.fromSeed(
        seedColor: seed ?? _fallbackSeed,
        brightness: Brightness.light,
      ));

  static ThemeData dark(Color? seed) =>
      _build(ColorScheme.fromSeed(
        seedColor: seed ?? _fallbackSeed,
        brightness: Brightness.dark,
      ));

  static ThemeData _build(ColorScheme s) {
    final base = ThemeData(colorScheme: s, useMaterial3: true);

    const shapeXs = BorderRadius.all(Radius.circular(4));   // extra-small
    const shapeM = BorderRadius.all(Radius.circular(12));    // medium
    const shapeL = BorderRadius.all(Radius.circular(16));    // large
    const shapeXl = BorderRadius.all(Radius.circular(28));   // extra-large

    return base.copyWith(
      scaffoldBackgroundColor: s.surface,

      // M3 顶部应用栏:surface 底色、无阴影、scroll-under 时不着色
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: s.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),

      cardTheme: CardTheme(
        color: s.surfaceContainerHigh,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: const RoundedRectangleBorder(borderRadius: shapeL),
        clipBehavior: Clip.antiAlias,
      ),

      // M3 文本输入:填充式 + extra-small 圆角(默认形态)
      // 聊天输入框的 28dp 圆角属于 search-bar 形态,在组件内单独指定
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHighest,
        border: const OutlineInputBorder(
            borderRadius: shapeXs, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(
            borderRadius: shapeXs, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: shapeXs,
          borderSide: BorderSide(color: s.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // M3 Snackbar:浮动、extra-small 圆角、限制宽度
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium
            ?.copyWith(color: s.onInverseSurface),
        shape: const RoundedRectangleBorder(borderRadius: shapeXs),
        insetPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        actionTextColor: s.inversePrimary,
        elevation: 6,
      ),

      // M3 对话框:28dp 圆角、24sp 标题
      dialogTheme: DialogTheme(
        backgroundColor: s.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: shapeXl),
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: s.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
        contentTextStyle:
            base.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant),
      ),

      // M3 底部表单:顶部 28dp 圆角 + 拖拽把手
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: s.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: s.onSurfaceVariant,
        elevation: 0,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: s.onSurfaceVariant,
        textColor: s.onSurface,
        titleTextStyle:
            base.textTheme.bodyLarge?.copyWith(color: s.onSurface),
        subtitleTextStyle:
            base.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant),
        shape: const RoundedRectangleBorder(borderRadius: shapeM),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: s.surfaceContainerHighest,
        side: BorderSide(color: s.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: base.textTheme.labelLarge?.copyWith(color: s.onSurface),
        deleteIconColor: s.onSurfaceVariant,
      ),

      dividerTheme: DividerThemeData(
        color: s.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),

      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: s.primary,
        inactiveTrackColor: s.surfaceContainerHighest,
        thumbColor: s.primary,
        overlayColor: s.primary.withAlpha(30),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: shapeL),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: base.textTheme.labelLarge,
        ),
      ),
    );
  }
}

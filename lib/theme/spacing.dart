import 'package:flutter/widgets.dart';

/// Material 3 间距系统(唯一来源)
///
/// 刻度(4dp 基准,与 M3 spacing scale 对齐):
///   4 / 8 / 12 / 16 / 24 / 32 / 40 / 48
///
/// 组件规范对应关系:
///   · 屏幕边距           16(compact 宽度)
///   · 区块之间           16–24
///   · 列表项水平内边距    16(高度由 ListTile 保证 ≥56)
///   · 卡片内边距         16
///   · 对话框内边距       24(AlertDialog 默认)
///   · 底部表单内边距     16,顶部拖拽把手由主题提供
///   · 图标按钮点击区     ≥48
///   · FAB 与内容安全距离 96(避免遮挡最后一项)
class Gap {
  const Gap._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;

  /// 列表底部留白:给 FAB 让位(FAB 56 + 边距 16 + 安全余量)
  static const double fabClearance = 96;

  /// 最小可点击尺寸(M3 无障碍要求)
  static const double minTouchTarget = 48;
}

/// 常用内边距组合(按组件规范)
class Insets {
  const Insets._();

  /// 页面级:左右 16,上 8,下 24
  static const page = EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xl);

  /// 列表:左右 16,上下 8
  static const list = EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm);

  /// 可滚动列表(底部给 FAB 让位)
  static const listWithFab =
      EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.fabClearance);

  /// 列表项水平内边距(M3:16)
  static const listItemHorizontal = EdgeInsets.symmetric(horizontal: Gap.lg);

  /// 卡片内边距:16 四周,底部略收
  static const card = EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md);

  /// 消息气泡内:水平 16 / 上 12 / 下 8
  static const bubble = EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.sm);

  /// 底部输入区域
  static const composer = EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md);

  /// 对话框内边距(M3:24)
  static const dialog = EdgeInsets.all(Gap.xl);

  /// 底部表单内容内边距
  static const sheet = EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm);
}

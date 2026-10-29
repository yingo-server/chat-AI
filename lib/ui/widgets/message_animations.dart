import 'package:flutter/material.dart';

/// 流式文本光标 — 内联在文字末尾(由 StreamingBubble 以 WidgetSpan 使用)。
/// 尺寸随文本样式走,避免写死像素;不参与语义树,独立重绘。
class BlinkingCursor extends StatefulWidget {
  final Color? color;
  final double? height;
  const BlinkingCursor({super.key, this.color, this.height});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 尊重"减少动态效果"设置:关闭动画时保持常亮
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final style = DefaultTextStyle.of(context).style;
    final h = widget.height ?? (style.fontSize != null ? style.fontSize! * 1.2 : 16);

    final bar = Container(
      width: 2,
      height: h,
      decoration: BoxDecoration(
        color: widget.color ?? Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(1),
      ),
    );

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: reduceMotion
            ? bar
            : FadeTransition(opacity: _opacity, child: bar),
      ),
    );
  }
}

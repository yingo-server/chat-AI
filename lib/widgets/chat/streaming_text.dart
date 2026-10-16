import 'package:flutter/material.dart';

import '../animation/message_animations.dart';

/// 流式文字 —— 逐字淡入 + 尾部光标。
///
/// 实现要点(性能优先):
/// - 只有"末尾一小段"参与淡入,前面的稳定文本合成单个 TextSpan,
///   因此每帧只新建约 [fadeLength] 个 span,长回复也不会掉帧;
/// - 每次文本增长即重启动画控制器,形成一个从左到右的淡入扫过效果;
/// - 颜色透明度随时间线性上升;不做位移动画,避免整段文字视觉抖动。
class StreamingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color? cursorColor;

  /// 参与淡入的尾部字符数
  final int fadeLength;

  /// 每段动画时长
  final Duration duration;

  /// 是否在文本末尾显示闪烁光标
  final bool showCursor;

  const StreamingText(
    this.text, {
    super.key,
    this.style,
    this.cursorColor,
    this.fadeLength = 12,
    this.duration = const Duration(milliseconds: 240),
    this.showCursor = true,
  });

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    _lastLength = widget.text.length;
  }

  @override
  void didUpdateWidget(covariant StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text.length != _lastLength) {
      _lastLength = widget.text.length;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Text.rich(
        _buildSpan(reduceMotion ? 1.0 : _ctrl.value),
        style: widget.style,
      ),
    );
  }

  TextSpan _buildSpan(double progress) {
    final text = widget.text;
    final style = widget.style ?? const TextStyle();
    final base = style.color ?? const Color(0xFF000000);

    if (text.isEmpty) return TextSpan(style: style, children: const []);

    final fadeLen = widget.fadeLength.clamp(1, 64).toInt();
    if (progress >= 1.0 || text.length <= 1) {
      return TextSpan(style: style, children: [
        TextSpan(text: text),
        if (widget.showCursor) _cursor(context),
      ]);
    }

    final splitAt =
        (text.length - fadeLen).clamp(0, text.length).toInt();
    final head = text.substring(0, splitAt);
    final tail = text.substring(splitAt);

    final spans = <InlineSpan>[];
    if (head.isNotEmpty) {
      spans.add(TextSpan(text: head, style: style));
    }
    // 尾部逐字淡入:越靠后(index 越大)出现越晚
    for (var i = 0; i < tail.length; i++) {
      final t =
          ((progress * fadeLen) - (tail.length - 1 - i)).clamp(0.0, 1.0);
      final alpha = 0.15 + 0.85 * t;
      spans.add(TextSpan(
        text: tail[i],
        style: style.copyWith(color: base.withAlpha((255 * alpha).round())),
      ));
    }
    if (widget.showCursor) spans.add(_cursor(context));
    return TextSpan(style: style, children: spans);
  }

  WidgetSpan _cursor(BuildContext context) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: BlinkingCursor(
            color: widget.cursorColor ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

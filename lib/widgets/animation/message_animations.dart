import 'package:flutter/material.dart';

/// 流式文本"打字机光标"动画
class BlinkingCursor extends StatefulWidget {
  final double height;
  final Color? color;
  const BlinkingCursor({super.key, this.height = 16, this.color});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? Theme.of(context).colorScheme.primary;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.0).animate(_ctrl),
      child: Container(
        width: 2,
        height: widget.height,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
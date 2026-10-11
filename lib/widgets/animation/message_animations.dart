import 'package:flutter/material.dart';

/// 消息入场 + 内容更新动画:
/// - 入场:fade + slide-up (ImplicitlyAnimated)
/// - 内容更新:AnimatedSwitcher 渐隐渐显
/// - 删除:AnimatedSize 收缩
class MessageAnimatedEntry extends StatelessWidget {
  final Widget child;
  final Key entryKey;
  const MessageAnimatedEntry(
      {super.key, required this.child, required this.entryKey});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: KeyedSubtree(key: entryKey, child: child),
      ),
    );
  }
}

/// 列表项淡入(整条消息首次出现)
class FadeInUp extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, t, c) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

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
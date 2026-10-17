import 'package:flutter/material.dart';

/// "正在思考"三点动画 —— 用于首 token 到达之前。
///
/// 三个点依次起伏(Fade + 轻微位移),周期 1.2s,遵循 M3 的
/// "attention indicator" 用法(不使用弹性过冲,避免抢注意力)。
/// 尊重系统"减少动态效果"设置。
class TypingDots extends StatefulWidget {
  final Color? color;
  final double size;

  const TypingDots({super.key, this.color, this.size = 6});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    if (reduceMotion) {
      return _dots(1.0, color);
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => _dots(_ctrl.value, color),
    );
  }

  Widget _dots(double t, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        // 每个点相位错开 1/3 周期,形成连续起伏
        final phase = (t + i / 3) % 1.0;
        final lift = phase < 0.5 ? phase * 2 : (1 - phase) * 2; // 0→1→0
        final opacity = 0.35 + 0.65 * lift;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.size * 0.45),
          child: Transform.translate(
            offset: Offset(0, -3 * lift),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: color.withAlpha((255 * opacity).round()),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

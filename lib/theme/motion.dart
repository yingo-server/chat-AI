import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Material Design 3 动效系统(唯一来源)
///
/// 参考:
/// - M3 Motion overview            https://m3.material.io/styles/motion/overview
/// - M3 Easing & duration tokens   https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
/// - M3 Expressive motion（弹簧）   https://m3.material.io/blog/m3-expressive-motion-theming
/// - Flutter Curves                https://api.flutter.dev/flutter/animation/Curves-class.html
/// - Flutter SpringSimulation      https://api.flutter.dev/flutter/physics/SpringSimulation-class.html
class Motion {
  const Motion._();

  // ── 缓动令牌 ────────────────────────────────────────────────
  /// md.sys.motion.easing.emphasized —— 主转场(收尾平滑)
  static const emphasized = Curves.easeInOutCubicEmphasized;

  /// md.sys.motion.easing.emphasized.decelerate —— 入场/展开
  static const emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// md.sys.motion.easing.emphasized.accelerate —— 退场/收起
  static const emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// md.sys.motion.easing.standard 系列
  static const standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // ── 时长令牌 ────────────────────────────────────────────────
  // M3 规定:多数过渡 ≤ 400ms;快速过渡 100–200ms
  static const short1 = Duration(milliseconds: 50);
  static const short2 = Duration(milliseconds: 100);
  static const short3 = Duration(milliseconds: 150);
  static const short4 = Duration(milliseconds: 200);
  static const medium1 = Duration(milliseconds: 250);
  static const medium2 = Duration(milliseconds: 300);
  static const long1 = Duration(milliseconds: 450);
  static const long2 = Duration(milliseconds: 500);

  // ── 弹簧令牌(M3 Expressive 物理系统)────────────────────────
  /// Spatial:Expressive —— 位置/尺寸/圆角等空间属性,允许轻微过冲
  static const spatial = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 30,
  );

  /// Spatial:Standard —— 功能型场景,回弹更小
  static const spatialStandard = SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 40,
  );

  /// Effects —— 颜色/透明度等属性,不得过冲(临界阻尼)
  static const effects = SpringDescription(
    mass: 1,
    stiffness: 1600,
    damping: 1,
  );
}

/// 以弹簧驱动控制器(M3 Expressive 的推荐做法)
void animateWithSpring(AnimationController c, SpringDescription spring,
    {double target = 1.0}) {
  c.animateWith(SpringSimulation(spring, c.value, target, 0.0));
}

/// 入场动画:仅对"最新一条"使用,避免列表滚动时重复播放
class MotionEntrance extends StatelessWidget {
  final Widget child;
  const MotionEntrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.medium1,
      curve: Motion.emphasizedDecelerate,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: c),
      ),
      child: child,
    );
  }
}

/// M3 风格页面转场:淡入 + 轻微上移(emphasized 曲线)
class EmphasizedPageTransitions extends PageTransitionsBuilder {
  const EmphasizedPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Motion.emphasizedDecelerate,
      reverseCurve: Motion.emphasizedAccelerate,
    );
    // 尊重系统"减少动态效果"
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || animation.status == AnimationStatus.completed) return child;

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

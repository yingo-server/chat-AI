# 附录 B —— 冷启动优化方案(含 M3 动效规范与着色器预编译调度)

文档版本 1.0 · 状态:建议性(Advisory)

本附录面向本应用的 Android 客户端,规定冷启动路径的优化方案。所有动效参数均以 Material Design 3 动效系统为基准;所有构建与调度建议均以 Flutter 官方文档为依据,并在文末给出引用清单。

---

## B.1 目标与度量

冷启动优化以三项指标为验收依据。其一为**首帧时间**(First Frame),即进程启动至 Flutter 首帧上屏的时长;其二为**首帧抖动**,即首帧前后的掉帧数量,主要来源于着色器编译与同步 I/O;其三为**可交互时间**,即用户可进行首次输入的时刻。

度量应在发布模式(`--profile`/`--release`)下,于代表性设备上使用 `flutter run --profile --trace-startup` 与 `flutter drive --profile --trace-startup` 采集轨迹,并以 DevTools 的 Timeline 视图比对优化前后。

---

## B.2 动效规范:Material Design 3

### B.2.1 动效物理系统(弹簧)

M3 Expressive 以**基于弹簧的物理系统**取代了旧的"缓动 + 时长"二元模型。弹簧由三个属性决定:`stiffness`(刚度,数值越高运动越快)、`damping`(阻尼,数值越高回弹衰减越快,取 1 表示临界阻尼、无过冲)、`initial velocity`(初速度)。

M3 提供两套预设:Expressive(推荐用于多数场景,尤其是关键交互)与 Standard(功能型产品,最小弹跳)。属性按用途分为两组:**Spatial spring tokens** 用于位置、旋转、尺寸、圆角等空间属性;**Effects spring tokens** 用于颜色、透明度等不应过冲的属性。

Flutter 侧可直接以 `SpringDescription` 描述弹簧,并以 `SpringSimulation` 驱动:

```dart
import 'package:flutter/physics.dart';

/// M3 Spatial:Expressive —— 用于位置/尺寸/圆角等空间属性(允许轻微过冲)
const kSpatialExpressive = SpringDescription(
  mass: 1,
  stiffness: 380,   // 关键交互取较高刚度,收束更快
  damping: 30,      // 阻尼偏低 → 保留少量回弹
);

/// M3 Effects:—— 用于颜色/透明度等属性(不得过冲,取临界阻尼)
const kEffects = SpringDescription(
  mass: 1,
  stiffness: 1600,
  damping: 1,       // 临界阻尼:无过冲
);

/// 以弹簧驱动 AnimationController,替代固定时长曲线
void driveSpring(AnimationController c, SpringDescription spring) {
  c.animateWith(SpringSimulation(spring, c.value, 1.0, 0.0));
}
```

```dart
/// 同时驱动多个空间属性(位置 + 圆角)时,共享同一弹簧以获得一致的物理观感
class SpringCard extends StatelessWidget {
  const SpringCard({super.key, required this.progress, required this.child});
  final double progress; // 0 → 1
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, (1 - progress) * 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16 + progress * 12),
        child: Opacity(opacity: progress, child: child),
      ),
    );
  }
}
```

### B.2.2 缓动与时长令牌(兼容路径)

在尚未采用弹簧、或需与既有实现保持一致时,应使用 M3 缓动令牌。其 Flutter 对应实现如下:

```dart
import 'package:flutter/animation.dart';

/// md.sys.motion.easing.emphasized
const kEmphasized = Curves.easeInOutCubicEmphasized;

/// md.sys.motion.easing.emphasized.decelerate —— 入场、展开
const kEmphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

/// md.sys.motion.easing.emphasized.accelerate —— 退场、收起
const kEmphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

/// md.sys.motion.easing.standard / standard.decelerate / standard.accelerate
const kStandard = Cubic(0.2, 0.0, 0.0, 1.0);
const kStandardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
const kStandardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);
```

时长令牌以"短—中—长"三档为骨架:短档取 50–200 毫秒(如短 4 为 200 毫秒),中档取 250–400 毫秒,长档取 450–600 毫秒用于大范围转场。**多数过渡应不超过 400 毫秒;快速过渡取 100–200 毫秒**。复杂动画应以硬件图层承载(在 Flutter 中体现为 `RepaintBoundary`、`Opacity` 的合成层优化与避免布局抖动的 `Transform` 类变换)。

本应用现有的动效取值经核对后建议调整为:发送/停止按钮的 `AnimatedSwitcher` 由 150 毫秒改为 200 毫秒并配 `kStandardAccelerate`;消息列表自动滚动由 200 毫秒 `easeOut` 改为 `kEmphasizedDecelerate` + 250 毫秒;对话切换的整表重建动画改为 **弹簧驱动**;流式光标的 600 毫秒循环闪烁保留(属"注意力指示"而非转场),但须遵循系统"减少动态效果"设置(本应用已实现)。

---

## B.3 着色器编译优化

### B.3.1 首选:Impeller

Impeller 在引擎构建期离线编译着色器,运行期不再触发编译,从根源上消除着色器编译引起的卡顿。在 Flutter 3.24.5 上,Android 端需显式启用:

```bash
flutter run   --profile --enable-impeller
flutter build apk --release --enable-impeller
```

启用后,应用应通过 `flutter doctor -v` 与运行期日志确认渲染后端为 Impeller;`--bundle-sksl-path` 一类的 SkSL 机制在 Impeller 下不适用,不应同时配置。

### B.3.2 备选:SkSL 预热(仅 Skia 后端)

当因设备兼容性或插件依赖性而必须驻留 Skia 后端时,按下列三步执行。

**步骤一:捕获。** 以 `--cache-sksl` 启动并**完整走查所有可能产生首帧编译的界面与动效**,包括页面转场、底部表单、对话框、以及列表滚动至出现新绘制效果的位置:

```bash
flutter run --profile --cache-sksl --purge-persistent-cache
# 走查完毕后,在终端按 M 导出 flutter_01.sksl.json
```

**步骤二:打包预编译。**

```bash
flutter build apk --release --bundle-sksl-path flutter_01.sksl.json
```

预编译工作在引擎首帧之前完成,从而把编译负载移出帧工作期。

**步骤三(可选):自定义预热。** 若需精细控制,可实现 `ShaderWarmUp` 子类,并在 `PaintingBinding` 初始化之前注入,使编译发生在启动阶段:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AppShaderWarmUp extends ShaderWarmUp {
  @override
  Future<void> warmUpOnCanvas(Canvas canvas) async {
    // 覆盖应用中会触发新着色器的绘制:圆角卡片、阴影、渐变、模糊
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(16),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(50, 50), 25, paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.shaderWarmUp = AppShaderWarmUp();
  runApp(const App());
}
```

### B.3.3 关于"每三日重新编译"的工程结论

SkSL 与 GPU 硬件及驱动相关,**不能跨设备复用**;因此定时任务的价值取决于其执行载体。本附录给出两种可行安排。

**安排一(推荐):在设备农场执行。** 以自建或托管的真机集群(覆盖目标机型的主要 GPU 系列)执行捕获,产物按"GPU 型号 + 驱动版本"归档,并在发布构建时按目标机型选择对应产物。

**安排二(可用但有明确限制):在托管 CI 的模拟器中执行。** GitHub 托管执行器可运行 Android 模拟器,但其 GPU 实现(`swiftshader_indirect` 软件渲染或宿主 GPU 透传)与真机不同,所捕获的 SkSL 仅能代表该模拟器环境,可作为**回归基线**,不应视作真机预热集。若采用此安排,应在归档说明中明确标注其局限。

两种安排均以三日为周期,并自动触发一次带 `--bundle-sksl-path` 的发布构建。完整调度配置见 B.5 节。

---

## B.4 冷启动整体优化

### B.4.1 原生层

**引擎预初始化。** 在 `Application.onCreate()` 中预创建 `FlutterEngine` 并放入 `FlutterEngineCache`,`MainActivity` 直接复用,避免在 `Activity` 创建时同步初始化引擎:

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        val loader = FlutterLoader()
        loader.startInitialization(this)                  // 后台预热引擎加载器
        loader.ensureInitializationComplete(this, null)
        FlutterEngineCache.getInstance().put("main", FlutterEngine(this).apply {
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
        })
    }
}

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get("main")
}
```

**代码与资源压缩。** 应启用 R8 的 `minifyEnabled` 与 `shrinkResources`,并以 AAB 形式分发。本应用已在 `tools/app.build.gradle` 中启用二者,且发布构建使用 `--obfuscate --split-debug-info`,无需另行调整。需注意:资源压缩会移除未引用的资源,故清单中凡需保留的资源(例如圆形启动图标)都必须被显式引用,否则将被剥离。

### B.4.2 Dart 层

**延迟非关键初始化。** 分析、推送等非关键 SDK 应推迟至首帧之后:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // 首帧之后执行:统计上报、推送注册、非首屏数据预取
  });
}
```

对本应用而言,`main()` 当前在 `runApp` **之前**同步完成了保险库初始化(FFI 调用、资源读取与解密)与配置文件读取(文件 I/O 与 JSON 解析)。这两项均属可后置工作:首页(对话列表)渲染并不依赖服务端点与密钥。建议改为:**立即 `runApp` 渲染首页骨架,并在首帧回调中完成保险库初始化与配置装载**,待完成后再通知界面刷新。若确需在首帧前完成,应使用 `WidgetsBinding.instance.deferFirstFrame()` / `allowFirstFrame()` 显式控制窗口,避免以同步 I/O 阻塞首帧。

**路由延迟加载。** 非首屏路由应使用延迟导入:

```dart
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart' deferred as chat;
import 'screens/settings_screen.dart' deferred as settings;

Future<void> openChat(BuildContext c, Object chatModel) async {
  await chat.loadLibrary();          // 首次进入时按需装载
  await Navigator.of(c).push(MaterialPageRoute(
    builder: (_) => chat.ChatScreen(chat: chatModel as dynamic),
  ));
}
```

**避免首帧重建。** 消息列表不应以"条数"作为 `ValueKey`(本应用已修正),否则每次追加消息都会整表重建,放大首帧与滚动开销。

### B.4.3 启动画面

应使用 `flutter_native_splash` 生成原生启动画面,并使背景色与 Logo 位置与 Flutter 首屏保持一致,以消除白屏与视觉跳变。本应用的界面底色取自淡灰蓝系,启动画面应取同色:

```yaml
# pubspec.yaml
flutter_native_splash:
  color: "#EDF1F7"                     # 与图标底色同族,避免闪白
  image: tools/res/source_icon.png      # 与自适应图标同源
  android_12:
    color: "#EDF1F7"
    icon_background_color: "#EDF1F7"
  fullscreen: true
```

```bash
dart run flutter_native_splash:create
```

---

## B.5 定时预编译的 CI 配置

以下工作流以三日为周期执行 SkSL 捕获与预编译打包。其执行载体为 Android 模拟器,故产物属**回归基线**(见 B.3.3 安排二):

```yaml
name: Shader precompile (every 3 days)

on:
  schedule:
    - cron: '0 2 */3 * *'      # 每三日 02:00 UTC
  workflow_dispatch:

permissions:
  contents: write

jobs:
  sksl:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.5'
          channel: stable

      - name: Enable KVM (accelerated emulator)
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.yaml') }}

      - name: Capture SkSL on emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          target: google_apis
          arch: x86_64
          profile: pixel_6
          emulator-options: -no-window -gpu swiftshader_indirect -no-snapshot -noaudio -no-boot-anim
          script: |
            flutter pub get
            flutter run --profile --cache-sksl --purge-persistent-cache &
            APP_PID=$!
            sleep 90
            # 以 adb 驱动界面走查,触发转场/弹窗/滚动
            adb shell input keyevent KEYCODE_WAKEUP
            adb shell input swipe 540 1600 540 400 300
            adb shell input keyevent KEYCODE_BACK
            adb shell input swipe 540 400 540 1600 300
            # 通过 stdin 发送 'M' 导出 flutter_01.sksl.json
            echo M > /proc/$APP_PID/fd/0 || true
            sleep 20
            kill $APP_PID || true
            ls -la flutter_01.sksl.json

      - name: Upload captured SkSL
        uses: actions/upload-artifact@v4
        with:
          name: sksl-capture
          path: flutter_01.sksl.json
          if-no-files-found: warn

      - name: Build with bundled SkSL (baseline)
        run: |
          if [ -f flutter_01.sksl.json ]; then
            flutter build apk --release --obfuscate \
              --split-debug-info=build/symbols \
              --bundle-sksl-path flutter_01.sksl.json
          else
            echo "::warning::No SkSL captured this run"
          fi

      - name: Upload baseline APK
        uses: actions/upload-artifact@v4
        with:
          name: apk-with-sksl
          path: build/app/outputs/flutter-apk/*.apk
          if-no-files-found: warn
```

关于 `flutter run` 的 stdin 交互需说明:在 CI 中向 `flutter run` 进程写入 `M` 以求导出文件,受终端属性影响并不稳定(该方式在多数环境下会因 stdin 非 TTY 而失败)。更可靠的做法是**在设备上以脚本化方式触发界面走查,并改用 `flutter drive` 配合自定义 `test_driver` 在测试结束时输出 SkSL**;若仍需依赖 `flutter run`,宜通过 `script -q /dev/null` 之类的伪终端包装器承载。

---

## B.6 实施顺序与验收

建议按下列顺序实施,并以可度量指标验收。首先完成 Dart 层的首帧解耦(保险库与配置装载后置)与启动画面接入,此两项风险最低、收益最直接,验收指标为首帧时间下降与白屏消失。其次启用 Impeller 并确认渲染后端,验收指标为首帧抖动归零。再次接入延迟路由加载与首帧后初始化,验收指标为首屏可交互时间下降。最后建立 SkSL 基线与定时任务,验收指标为首帧编译类掉帧在 Skia 路径下消除或显著减少。

---

## B.7 引用

Material Design 3 动效规范:<https://m3.material.io/styles/motion/overview>;过渡模式:<https://m3.material.io/styles/motion/transitions>;缓动与时长令牌:<https://m3.material.io/styles/motion/easing-and-duration/tokens-specs>;弹簧物理说明(Expressive motion):<https://m3.material.io/blog/m3-expressive-motion-theming>。

Flutter 性能与渲染:Impeller 概览:<https://docs.flutter.dev/perf/impeller>;着色器编译卡顿与 SkSL 预热:<https://docs.flutter.dev/perf/shader>;性能最佳实践:<https://docs.flutter.dev/perf/best-practices>;延迟组件与延迟导入:<https://docs.flutter.dev/perf/deferred-components>。

Flutter API:`SpringDescription`:<https://api.flutter.dev/flutter/physics/SpringDescription-class.html>;`SpringSimulation`:<https://api.flutter.dev/flutter/physics/SpringSimulation-class.html>;`Curves`(含 `easeInOutCubicEmphasized`):<https://api.flutter.dev/flutter/animation/Curves-class.html>;`ShaderWarmUp`:<https://api.flutter.dev/flutter/rendering/ShaderWarmUp-class.html>;`WidgetsBinding.deferFirstFrame`:<https://api.flutter.dev/flutter/widgets/WidgetsBinding-class.html>。

其他:`flutter_native_splash`:<https://pub.dev/packages/flutter_native_splash>;Android 模拟器执行器:<https://github.com/ReactiveCircus/android-emulator-runner>。

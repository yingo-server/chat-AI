import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/app_config.dart';
import 'ui/screens/home_screen.dart';
import 'core/config/config_store.dart';
import 'core/theme/app_theme.dart';
import 'core/vault/vault.dart' as vault;

/// 冷启动路径(优化后):
///   1. 仅完成最小必要初始化,随即 runApp —— 首帧不再等待 I/O 与解密
///   2. 保险库解密与配置装载在首帧之后异步执行,完成后通知界面刷新
///   3. 需要配置的页面(对话窗口)等待 `ConfigScope.ready` 后再取用
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 屏幕方向:不阻塞首帧,异步设置
  unawaited(SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]));

  runApp(AIChatApp(store: ConfigStore()));
}

class AIChatApp extends StatefulWidget {
  final ConfigStore store;
  const AIChatApp({super.key, required this.store});

  @override
  State<AIChatApp> createState() => _AIChatAppState();
}

class _AIChatAppState extends State<AIChatApp> {
  /// 默认字号(与 UserPrefs.defaults.fontSize 一致)
  static const _baseFontSize = 15.0;

  final ConfigController _controller = ConfigController();

  /// 首帧之后完成的初始化:保险库解密 + 配置装载
  late final Future<void> _ready = _bootstrapAfterFirstFrame();

  Future<void> _bootstrapAfterFirstFrame() async {
    // 让步给首帧
    await WidgetsBinding.instance.endOfFrame;
    final rc = await vault.Vault.init();
    if (rc != 0) debugPrint('[vault] init failed: $rc');

    AppConfig cfg;
    try {
      cfg = await widget.store.load();
    } catch (e) {
      debugPrint('[config] load failed: $e');
      cfg = AppConfig.empty();
    }
    _controller.replace(AppConfig(
      ai: AiConfig.fromVault(),
      context: cfg.context,
      recurringPrompts: cfg.recurringPrompts,
      systemPrompts: cfg.systemPrompts,
      userPrefs: cfg.userPrefs,
    ));
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      widget.store.save(_controller.config);
    });
  }

  Color? _seedColor() {
    final idx = _controller.config.userPrefs.seedColorIndex;
    if (idx < 0 || idx >= UserPrefs.seedColors.length) return null;
    return Color(UserPrefs.seedColors[idx]);
  }

  @override
  Widget build(BuildContext context) {
    return ConfigScope(
      controller: _controller,
      store: widget.store,
      ready: _ready,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final seed = _seedColor();
          return MaterialApp(
            title: 'AI Chat',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(seed),
            darkTheme: AppTheme.dark(seed),
            home: const HomeScreen(),
            builder: (ctx, child) {
              // 全局字号:用户偏好 × 系统缩放(M3 统一字级)
              final mq = MediaQuery.of(ctx);
              final factor =
                  _controller.config.userPrefs.fontSize / _baseFontSize;
              final systemScale = mq.textScaler.scale(1.0);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(systemScale * factor),
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}

class ConfigScope extends InheritedWidget {
  final ConfigController controller;
  final ConfigStore store;

  /// 首帧后完成:保险库就绪 + 配置已装载
  final Future<void> ready;

  const ConfigScope({
    super.key,
    required this.controller,
    required this.store,
    required this.ready,
    required super.child,
  });

  static ConfigScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ConfigScope>();
    assert(scope != null, 'ConfigScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(ConfigScope oldWidget) =>
      controller != oldWidget.controller || ready != oldWidget.ready;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_config.dart';
import 'screens/home_screen.dart';
import 'services/config_store.dart';
import 'theme/app_theme.dart';
import 'utils/vault.dart' as vault;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  } catch (_) {/* 桌面/测试环境忽略 */}

  // 1) 初始化原生保险库(master 已混淆嵌入 libvault.so)
  final rc = await vault.Vault.init();
  if (rc != 0) {
    debugPrint('[vault] init failed: $rc');
  }

  // 2) 读取本地配置(不含端点/密钥)
  final store = ConfigStore();
  AppConfig cfg;
  try {
    cfg = await store.load();
  } catch (e) {
    debugPrint('[config] load failed: $e');
    cfg = AppConfig.empty();
  }

  // 3) 端点/密钥来自原生保险库
  final config = AppConfig(
    ai: AiConfig.fromVault(),
    context: cfg.context,
    recurringPrompts: cfg.recurringPrompts,
    systemPrompts: cfg.systemPrompts,
    userPrefs: cfg.userPrefs,
  );

  runApp(AIChatApp(store: store, initialConfig: config));
}

class AIChatApp extends StatefulWidget {
  final ConfigStore store;
  final AppConfig initialConfig;
  const AIChatApp({
    super.key,
    required this.store,
    required this.initialConfig,
  });

  @override
  State<AIChatApp> createState() => _AIChatAppState();
}

class _AIChatAppState extends State<AIChatApp> {
  /// 默认字号(与 UserPrefs.defaults.fontSize 保持一致)
  static const _baseFontSize = 15.0;

  late final ConfigController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfigController()..replace(widget.initialConfig);
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
              // 全局字号:用户偏好 × 系统字体缩放。
              // 这样所有文本(标题/正文/按钮/标签)按同一比例缩放,
              // 符合 M3「统一字级」原则,而不是只改某几个 textStyle。
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

  const ConfigScope({
    super.key,
    required this.controller,
    required this.store,
    required super.child,
  });

  static ConfigScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ConfigScope>();
    assert(scope != null, 'ConfigScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(ConfigScope oldWidget) =>
      controller != oldWidget.controller;
}

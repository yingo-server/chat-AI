import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_config.dart';
import 'screens/home_screen.dart';
import 'services/config_store.dart';
import 'theme/app_theme.dart';
import 'utils/vault.dart' as vault;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // 1) 启动 native vault(加载 assets/vault.bin;master 内嵌于 native 库)
  final r = await vault.Vault.init();
  if (r != 0) debugPrint('vault init: $r');
  // 即便 vault init 失败也继续(返回空 endpoint/key,UI 由 isValid 弹出 请检查配置)

  // 2) 加载 config.json(只含 prefs/context/prompts)
  final store = ConfigStore();
  final cfg = await store.load();

  // 3) 把 vault 端点/密钥塞入 AiConfig
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
              final t = Theme.of(ctx);
              final fs = _controller.config.userPrefs.fontSize.toDouble();
              return Theme(
                data: t.copyWith(
                  textTheme: t.textTheme.copyWith(
                    bodyMedium:
                        t.textTheme.bodyMedium?.copyWith(fontSize: fs),
                    bodySmall:
                        t.textTheme.bodySmall?.copyWith(fontSize: fs - 1),
                    titleSmall:
                        t.textTheme.titleSmall?.copyWith(fontSize: fs + 1),
                    titleMedium:
                        t.textTheme.titleMedium?.copyWith(fontSize: fs + 2),
                  ),
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
    final scope =
        context.dependOnInheritedWidgetOfExactType<ConfigScope>();
    assert(scope != null, 'ConfigScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(ConfigScope oldWidget) =>
      controller != oldWidget.controller;
}
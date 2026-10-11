import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_config.dart';
import 'screens/home_screen.dart';
import 'services/config_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // 触发首次配置初始化(把示例配置写入文档目录)
  final store = ConfigStore();
  await store.load();

  runApp(AIChatApp(store: store));
}

class AIChatApp extends StatefulWidget {
  final ConfigStore store;
  const AIChatApp({super.key, required this.store});

  @override
  State<AIChatApp> createState() => _AIChatAppState();
}

class _AIChatAppState extends State<AIChatApp> {
  final _controller = ConfigController();

  @override
  Widget build(BuildContext context) {
    return ConfigScope(
      controller: _controller,
      store: widget.store,
      child: MaterialApp(
        title: 'AI Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(null),
        darkTheme: AppTheme.dark(null),
        home: const HomeScreen(),
      ),
    );
  }
}

/// InheritedWidget — 给屏幕提供 ConfigController / ConfigStore
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
    assert(scope != null, 'ConfigScope missing in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(ConfigScope oldWidget) =>
      controller != oldWidget.controller;
}
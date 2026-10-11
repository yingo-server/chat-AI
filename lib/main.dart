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

  final store = ConfigStore();
  final initialCfg = await store.load();

  runApp(AIChatApp(store: store, initialConfig: initialCfg));
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

/// InheritedWidget
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
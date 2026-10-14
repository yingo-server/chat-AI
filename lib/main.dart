import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_config.dart';
import 'screens/home_screen.dart';
import 'services/config_store.dart';
import 'theme/app_theme.dart';
import 'utils/error_code.dart';
import 'utils/vault.dart' as vault;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  } catch (e, st) {
    throw AppError(Ec.main01.code, Ec.main01.message, cause: e, stack: st);
  }

  // 1) 启动 native vault
  int ec;
  try {
    ec = await vault.Vault.init();
  } catch (e, st) {
    if (e is AppError) {
      runApp(FatalErrorScreen(error: e));
      return;
    }
    runApp(FatalErrorScreen(
        error: AppError(Ec.main03.code, Ec.main03.message, cause: e, stack: st)));
    return;
  }
  if (ec != 0) {
    runApp(FatalErrorScreen(
        error: AppError(ec, 'vault.init failed: $ec')));
    return;
  }

  // 2) config store
  late ConfigStore store;
  try {
    store = ConfigStore();
    await store.load();
  } catch (e, st) {
    runApp(FatalErrorScreen(
        error: AppError(Ec.main02.code, Ec.main02.message, cause: e, stack: st)));
    return;
  }

  // 3) 构造 AppConfig
  late AppConfig config;
  try {
    final cfg = await store.load();
    final (ai, aiEc) = AiConfig.fromVaultWithEc();
    if (ai == null) {
      runApp(FatalErrorScreen(
          error: AppError(aiEc, 'AiConfig.fromVault failed: $aiEc')));
      return;
    }
    config = AppConfig(
      ai: ai,
      context: cfg.context,
      recurringPrompts: cfg.recurringPrompts,
      systemPrompts: cfg.systemPrompts,
      userPrefs: cfg.userPrefs,
    );
  } catch (e, st) {
    runApp(FatalErrorScreen(
        error: AppError(Ec.main04.code, Ec.main04.message, cause: e, stack: st)));
    return;
  }

  try {
    runApp(AIChatApp(store: store, initialConfig: config));
  } catch (e, st) {
    runApp(FatalErrorScreen(
        error: AppError(Ec.main05.code, Ec.main05.message, cause: e, stack: st)));
  }
}

class FatalErrorScreen extends StatelessWidget {
  final AppError error;
  const FatalErrorScreen({super.key, required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                const SizedBox(height: 16),
                Text('启动失败',
                    style: const TextStyle(color: Colors.white, fontSize: 20)),
                const SizedBox(height: 8),
                Text(error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      try {
        widget.store.save(_controller.config);
      } catch (e, st) {
        debugPrint('save config failed: ${AppError(Ec.cfg01.code, Ec.cfg01.message, cause: e, stack: st)}');
      }
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
          try {
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
          } catch (e, st) {
            debugPrint('build failed: ${AppError(Ec.th01.code, Ec.th01.message, cause: e, stack: st)}');
            return MaterialApp(
              home: FatalErrorScreen(
                  error: AppError(Ec.th01.code, Ec.th01.message, cause: e, stack: st)),
            );
          }
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
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';

/// 配置文件持久层
/// - 启动时:`assets/config.example.json` → 文档目录 `config.json`
/// - 写入:端点 / apiKey 通过 SecretField 自动 XOR + base64
/// - 编译期可通过 `--dart-define=API_ENDPOINT=...` 与 `--dart-define=API_KEY=...`
///   注入真实值(仓库里只放占位符,避免泄密)
class ConfigStore {
  static const _fileName = 'config.json';
  static const _saltFileName = '.chat_ai_salt';

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  Future<File> _saltFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _saltFileName));
  }

  Future<AppConfig> load() async {
    final f = await _file();
    if (!await f.exists()) {
      final asset = await rootBundle.loadString('assets/config.example.json');
      await f.writeAsString(asset);
    }
    var raw = await f.readAsString();
    if (raw.trim().isEmpty) return _withDartDefines(AppConfig.empty());

    var cfg = AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);

    // 若 endpoint / apiKey 是空的,用 --dart-define 注入(只发生在内存,不修改磁盘文件)
    cfg = _withDartDefines(cfg);
    return cfg;
  }

  /// 把编译期 dart-define 注入到空字段(只用于运行时,不入磁盘)
  AppConfig _withDartDefines(AppConfig cfg) {
    const envEndpoint =
        String.fromEnvironment('API_ENDPOINT', defaultValue: '');
    const envKey = String.fromEnvironment('API_KEY', defaultValue: '');
    const envModel =
        String.fromEnvironment('API_MODEL', defaultValue: '');
    var ai = cfg.ai;
    if (ai.endpoint.isEmpty && envEndpoint.isNotEmpty) {
      ai = ai.copyWith(endpoint: envEndpoint);
    }
    if (ai.apiKey.isEmpty && envKey.isNotEmpty) {
      ai = ai.copyWith(apiKey: envKey);
    }
    if (envModel.isNotEmpty && envModel != ai.model) {
      ai = ai.copyWith(model: envModel);
    }
    if (ai != cfg.ai) {
      cfg = cfg.copyWith(ai: ai);
    }
    return cfg;
  }

  Future<void> save(AppConfig cfg) async {
    final f = await _file();
    final passphrase = await _passphrase();
    await f.writeAsString(cfg.encode(secretPassphrase: passphrase));
  }

  Future<String> _passphrase() async {
    final s = await _saltFile();
    if (await s.exists()) {
      return (await s.readAsString()).trim();
    }
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    final pass = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await s.writeAsString(pass);
    return pass;
  }
}
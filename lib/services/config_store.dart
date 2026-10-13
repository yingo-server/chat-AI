import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';

/// 配置文件持久层(只保存用户偏好和提示词;端点 / 密钥由 native vault 保护)
class ConfigStore {
  static const _fileName = 'config.json';

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, _fileName));
  }

  /// 启动时加载;若不存在,从 assets 拷一份
  Future<AppConfig> load() async {
    final f = await _file();
    if (!await f.exists()) {
      try {
        final asset =
            await rootBundle.loadString('assets/config.example.json');
        await f.writeAsString(asset);
      } catch (_) {
        // asset 缺失也允许
      }
    }
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return AppConfig.empty();
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppConfig.empty();
    }
  }

  /// 持久化(endpoint/apiKey 不会进文件 — vault 单独保护)
  Future<void> save(AppConfig cfg) async {
    final f = await _file();
    await f.writeAsString(cfg.encode());
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';

/// 配置文件存储在应用文档目录下的 `config.json`。
/// 首次启动从 assets 拷贝示例配置。
class ConfigStore {
  static const _fileName = 'config.json';

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    final f = File(p.join(docs.path, _fileName));
    if (!await f.exists()) {
      // 从打包资源初始化
      final asset = await _readAsset();
      await f.writeAsString(asset);
    }
    return f;
  }

  Future<String> _readAsset() async {
    // 优先读取自定义 assets/config.json,fallback 到示例
    // 实际加载在 main() 中通过 rootBundle 完成,此处给个安全默认值。
    return const JsonEncoder.withIndent('  ').convert({
      'ai': {
        'endpoint': '',
        'apiKey': '',
        'model': 'gpt-4o-mini',
        'temperature': 0.7,
        'maxTokens': 2048,
        'requestTimeoutSeconds': 120,
      },
      'context': {
        'maxContextMessages': 40,
        'compressTriggerMessages': 30,
        'keepRecentMessages': 12,
        'compressPrompt':
            '请把以下对话历史压缩成客观摘要,保留关键事实和约定,不超过 300 字。',
        'compressModel': '',
      },
      'recurringPrompts': <Map<String, dynamic>>[],
      'systemPrompts': [
        {
          'id': 'default',
          'name': '默认助手',
          'content': '你是一个 helpful 的中文助手。回答简洁、准确。',
        }
      ],
    });
  }

  Future<AppConfig> load() async {
    final f = await _file();
    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return AppConfig.empty();
    return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AppConfig cfg) async {
    final f = await _file();
    await f.writeAsString(cfg.encode());
  }
}
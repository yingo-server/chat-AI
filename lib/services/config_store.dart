import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../utils/error_code.dart';

/// 配置文件存储(只含 prefs/context/prompts;endpoint/key 在 native vault)
/// 所有失败抛 AppError
class ConfigStore {
  static const _fileName = 'config.json';

  Future<File> _file() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return File(p.join(docs.path, _fileName));
    } catch (e, st) {
      throw AppError(Ec.cfg09.code, Ec.cfg09.message, cause: e, stack: st);
    }
  }

  /// 0=成功(从 assets 拷了默认),1=已存在,其他=错误码
  /// 抛 AppError
  Future<AppConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        try {
          final asset =
              await rootBundle.loadString('assets/config.example.json');
          await f.writeAsString(asset);
        } on AppError {
          rethrow;
        } catch (e, st) {
          throw AppError(Ec.cfg01.code, Ec.cfg01.message, cause: e, stack: st);
        }
      }
      String raw;
      try {
        raw = await f.readAsString();
      } catch (e, st) {
        throw AppError(Ec.cfg00.code, Ec.cfg00.message, cause: e, stack: st);
      }
      if (raw.trim().isEmpty) return AppConfig.empty();
      try {
        return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on AppError {
        rethrow;
      } catch (e, st) {
        throw AppError(Ec.cfg02.code, Ec.cfg02.message, cause: e, stack: st);
      }
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.cfg00.code, Ec.cfg00.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> save(AppConfig cfg) async {
    try {
      final f = await _file();
      await f.writeAsString(cfg.encode());
      return 0;
    } catch (e, st) {
      throw AppError(Ec.cfg01.code, Ec.cfg01.message, cause: e, stack: st);
    }
  }
}
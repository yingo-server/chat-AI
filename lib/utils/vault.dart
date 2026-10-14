// lib/utils/vault.dart — 高层封装:从 secure storage 拿 master key,初始化 native vault
// 所有函数返回 int 错误码(0=成功)或抛 AppError
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../native/vault_ffi.dart';
import 'error_code.dart';

class Vault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _masterAlias = 'chat_ai_master_v1';

  static bool _initialized = false;
  static bool get initialized => _initialized;

  /// 0 = 成功, 非 0 = 错误码
  static Future<int> init() async {
    if (_initialized) return 0;
    try {
      // 1. 拿/生成 master key
      final (master, ec) = await _loadOrCreateMaster();
      if (ec != 0) return ec;
      if (master.length != 32) return Ec.vlt01.code;

      // 2. 加载 vault.bin
      late Uint8List vaultBin;
      try {
        final bin = await rootBundle.load('assets/vault.bin');
        vaultBin = Uint8List.fromList(
            bin.buffer.asUint8List(bin.offsetInBytes, bin.lengthInBytes));
      } catch (e, st) {
        throw AppError(Ec.vlt05.code, Ec.vlt05.message, cause: e, stack: st);
      }

      // 3. 传给 native
      final sm = VaultFfi.setMaster(master);
      if (sm != 0) return sm; // 错误码

      // 4. init
      final r = VaultFfi.init(vaultBin);

      // 5. wipe Dart 端
      master.fillRange(0, master.length, 0);

      _initialized = (r == 0);
      return r;
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.vlt00.code, Ec.vlt00.message, cause: e, stack: st);
    }
  }

  /// 加载或生成 master key;返回 (key, errorCode)
  static Future<(Uint8List, int)> _loadOrCreateMaster() async {
    try {
      final stored = await _storage.read(key: _masterAlias);
      if (stored != null && stored.isNotEmpty) {
        return (base64Decode(stored), 0);
      }
      final rnd = Random.secure();
      final m = Uint8List(32);
      for (var i = 0; i < 32; i++) m[i] = rnd.nextInt(256);
      await _storage.write(key: _masterAlias, value: base64Encode(m));
      return (m, 0);
    } catch (e, st) {
      throw AppError(Ec.vlt03.code, Ec.vlt03.message, cause: e, stack: st);
    }
  }

  /// 0 = 成功,8 位错误码 = 失败
  /// [outEc] 是 native 返回的错误码(0=成功)
  static (String?, int) endpoint() {
    final (v, ec) = VaultFfi.getEndpoint();
    if (ec != 0) return (null, ec);
    if (v == null || v.isEmpty) return (null, Ec.vlt08.code);
    return (v, 0);
  }

  static (String?, int) apiKey() {
    final (v, ec) = VaultFfi.getApiKey();
    if (ec != 0) return (null, ec);
    if (v == null || v.isEmpty) return (null, Ec.vlt09.code);
    return (v, 0);
  }

  static int wipe() {
    try {
      VaultFfi.wipe();
      _initialized = false;
      return 0;
    } catch (e) {
      return Ec.vlt00.code;
    }
  }
}
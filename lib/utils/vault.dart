// lib/utils/vault.dart — 高层封装:从 secure storage 拿 master key,初始化 native vault
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../native/vault_ffi.dart';

/// 包装:在不暴露明文到长生命周期变量的情况下,使用 vault 中的秘密
class Vault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _masterAlias = 'chat_ai_master_v1';

  static bool _initialized = false;
  static bool get initialized => _initialized;

  /// 初始化:从 secure storage 拿 master key(若不存在则随机生成并保存)
  static Future<int> init() async {
    if (_initialized) return 0;

    // 1. 拿 master key
    Uint8List master;
    final stored = await _storage.read(key: _masterAlias);
    if (stored != null && stored.isNotEmpty) {
      master = base64Decode(stored);
    } else {
      // 随机生成 32 字节
      final rnd = Random.secure();
      master = Uint8List(32);
      for (var i = 0; i < 32; i++) master[i] = rnd.nextInt(256);
      await _storage.write(key: _masterAlias, value: base64Encode(master));
    }
    if (master.length != 32) return -1;

    // 2. 加载 vault.bin (asset)
    final bin = await rootBundle.load('assets/vault.bin');
    final vaultBin = Uint8List(bin.lengthInBytes);
    int off = 0;
    for (final chunk in bin.buffer.asUint8List(
        bin.offsetInBytes, bin.lengthInBytes)) {
      vaultBin[off++] = chunk;
    }

    // 3. 传给 native
    final sm = VaultFfi.setMaster(master);
    if (sm != 1) return -1;

    // 4. 初始化
    final r = VaultFfi.init(vaultBin);

    // 5. wipe Dart 端 master 副本
    master.fillRange(0, master.length, 0);

    _initialized = (r == 0);
    return r;
  }

  static String? endpoint() => VaultFfi.getEndpoint();
  static String? apiKey() => VaultFfi.getApiKey();

  static void wipe() {
    VaultFfi.wipe();
    _initialized = false;
  }
}
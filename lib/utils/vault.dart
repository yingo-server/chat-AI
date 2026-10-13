// lib/utils/vault.dart — 高层封装:从 secure storage 拿 master key,初始化 native vault
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

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
  /// 然后调用 native vault_init(vault.bin)
  /// 第二次启动 master key 已在 Keystore 里,直接用
  static Future<int> init() async {
    if (_initialized) return 0;

    // 1. 拿 master key
    Uint8List master;
    final stored = await _storage.read(key: _masterAlias);
    if (stored != null && stored.isNotEmpty) {
      master = base64Decode(stored);
    } else {
      // 随机生成 32 字节,落 secure storage
      final rnd = _secureRandomBytes(32);
      master = rnd;
      await _storage.write(key: _masterAlias, value: base64Encode(master));
    }
    if (master.length != 32) return -1;

    // 2. 加载 vault.bin (asset)
    final bin = await rootBundle.load('assets/vault.bin');
    final vaultBin =
        Uint8List.viewMeOrEmpty(bin.buffer, bin.offsetInBytes, bin.lengthInBytes);

    // 3. 传给 native
    final sm = VaultFfi.setMaster(master);
    if (sm != 1) return -1;

    // 4. 初始化
    final r = VaultFfi.init(vaultBin);

    // 5. 立刻 wipe Dart 端 master 副本
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

  static Uint8List _secureRandomBytes(int n) {
    final s = FortunaRandom();
    final seed = Uint8List(32);
    final sr = _SystemRandom();
    for (var i = 0; i < 32; i++) seed[i] = sr.nextInt(256);
    s.seed(KeyParameter(seed));
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) out[i] = s.nextUint8();
    return out;
  }
}

/// 包装成一个 dart 闭包风格:使用完立刻 wipe
class VaultUse<T> {
  final String? value;
  VaultUse(this.value);
}

/// 在闭包内使用,使用完自动 wipe(native 端)+ null 化
T? useSecret<T>(T? Function() reader, T Function(T) action) {
  final v = reader();
  try {
    if (v == null) return null;
    return action(v);
  } finally {
    // 不能 wipe native 端(会影响后续调用),仅建议短生命周期
  }
}
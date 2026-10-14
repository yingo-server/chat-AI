// lib/utils/vault.dart — 高层封装:从 asset 加载 vault.bin 并初始化 native vault
// master key 已内嵌于 native 库(由 CI 生成 vault_master.h),无需 Dart 端管理
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../native/vault_ffi.dart';

/// 包装:在不暴露明文到长生命周期变量的情况下,使用 vault 中的秘密
class Vault {
  static bool _initialized = false;
  static bool get initialized => _initialized;

  /// 初始化:加载 assets/vault.bin 交给 native 层(master 已内嵌于 native 库)
  static Future<int> init() async {
    if (_initialized) return 0;

    ByteData bin;
    try {
      bin = await rootBundle.load('assets/vault.bin');
    } catch (_) {
      return -12000005; // asset 加载失败
    }
    final vaultBin = Uint8List.fromList(
        bin.buffer.asUint8List(bin.offsetInBytes, bin.lengthInBytes));

    final r = VaultFfi.init(vaultBin);
    _initialized = (r == 0);
    return r;
  }

  /// 返回 (endpoint, 0) 或 (null, 错误码)
  static (String?, int) endpoint() {
    if (!_initialized) return (null, -12000002);
    final (s, code) = VaultFfi.getEndpoint();
    if (code != 0) return (null, code);
    if (s == null || !(s.startsWith('http://') || s.startsWith('https://'))) {
      return (null, -12000008);
    }
    return (s, 0);
  }

  /// 返回 (apiKey, 0) 或 (null, 错误码)
  static (String?, int) apiKey() {
    if (!_initialized) return (null, -12000002);
    final (s, code) = VaultFfi.getApiKey();
    if (code != 0) return (null, code);
    if (s == null || s.isEmpty) return (null, -12000009);
    return (s, 0);
  }

  static void wipe() {
    VaultFfi.wipe();
    _initialized = false;
  }
}

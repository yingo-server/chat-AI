// lib/native/vault_ffi.dart — FFI 绑定到 libvault.so
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// 导出符号(从 vault.cpp,带 visibility("default"))
typedef _VaultInitNative = Int32 Function(
    Pointer<Uint8> vaultBin, Int32 vaultLen);
typedef _VaultInitDart = int Function(Pointer<Uint8> vaultBin, int vaultLen);

typedef _VaultSetMasterNative = Int32 Function(
    Pointer<Uint8> key, Int32 len);
typedef _VaultSetMasterDart = int Function(Pointer<Uint8> key, int len);

typedef _VaultGetStrNative = Int32 Function(
    Pointer<Uint8> out, Int32 outLen);
typedef _VaultGetStrDart = int Function(Pointer<Uint8> out, int outLen);

typedef _VaultWipeNative = Void Function();
typedef _VaultWipeDart = void Function();

class VaultFfi {
  static final DynamicLibrary _lib = _loadLib();

  static DynamicLibrary _loadLib() {
    if (Platform.isAndroid) return DynamicLibrary.open('libvault.so');
    if (Platform.isLinux) return DynamicLibrary.open('libvault.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libvault.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('vault.dll');
    return DynamicLibrary.process();
  }

  static late final _VaultInitDart _init =
      _lib.lookupFunction<_VaultInitNative, _VaultInitDart>('vault_init');
  static late final _VaultSetMasterDart _setMaster =
      _lib.lookupFunction<_VaultSetMasterNative, _VaultSetMasterDart>(
          'vault_set_master');
  static late final _VaultGetStrDart _get =
      _lib.lookupFunction<_VaultGetStrNative, _VaultGetStrDart>(
          'vault_get_endpoint');
  static late final _VaultGetStrDart _getKey =
      _lib.lookupFunction<_VaultGetStrNative, _VaultGetStrDart>(
          'vault_get_api_key');
  static late final _VaultWipeDart _wipe =
      _lib.lookupFunction<_VaultWipeNative, _VaultWipeDart>('vault_wipe');

  static int init(Uint8List vaultBin) {
    final ptr = malloc<Uint8>(vaultBin.length);
    try {
      ptr.asTypedList(vaultBin.length).setAll(0, vaultBin);
      return _init(ptr, vaultBin.length);
    } finally {
      malloc.free(ptr);
    }
  }

  static int setMaster(Uint8List key) {
    final ptr = malloc<Uint8>(key.length);
    try {
      ptr.asTypedList(key.length).setAll(0, key);
      return _setMaster(ptr, key.length);
    } finally {
      ptr.asTypedList(key.length).fillRange(0, key.length, 0);
      malloc.free(ptr);
    }
  }

  static String? getEndpoint() => _readStr(_get);
  static String? getApiKey() => _readStr(_getKey);

  static String? _readStr(int Function(Pointer<Uint8>, int) f) {
    final buf = malloc<Uint8>(1024);
    try {
      final n = f(buf, 1024);
      if (n <= 0) return null;
      // C 字符串以 \0 结尾
      var len = 0;
      while (len < n && buf[len] != 0) len++;
      final bytes = Uint8List(len);
      for (var i = 0; i < len; i++) bytes[i] = buf[i];
      return String.fromCharCodes(bytes);
    } finally {
      malloc.free(buf);
    }
  }

  static void wipe() => _wipe();
}
// lib/native/vault_ffi.dart — FFI 绑定到 libvault.so
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../utils/error_code.dart';

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
    try {
      if (Platform.isAndroid) return DynamicLibrary.open('libvault.so');
      if (Platform.isLinux) return DynamicLibrary.open('libvault.so');
      if (Platform.isMacOS) return DynamicLibrary.open('libvault.dylib');
      if (Platform.isWindows) return DynamicLibrary.open('vault.dll');
      return DynamicLibrary.process();
    } catch (e, st) {
      throw AppError(Ec.vlt00.code, Ec.vlt00.message, cause: e, stack: st);
    }
  }

  static late final _VaultInitDart _init;
  static late final _VaultSetMasterDart _setMaster;
  static late final _VaultGetStrDart _get;
  static late final _VaultGetStrDart _getKey;
  static late final _VaultWipeDart _wipe;

  static bool _ready = false;
  static void _ensure() {
    if (_ready) return;
    try {
      _init = _lib
          .lookupFunction<_VaultInitNative, _VaultInitDart>('vault_init');
      _setMaster = _lib.lookupFunction<_VaultSetMasterNative, _VaultSetMasterDart>(
          'vault_set_master');
      _get = _lib.lookupFunction<_VaultGetStrNative, _VaultGetStrDart>(
          'vault_get_endpoint');
      _getKey = _lib.lookupFunction<_VaultGetStrNative, _VaultGetStrDart>(
          'vault_get_api_key');
      _wipe = _lib.lookupFunction<_VaultWipeNative, _VaultWipeDart>('vault_wipe');
      _ready = true;
    } catch (e, st) {
      throw AppError(Ec.vlt11.code, Ec.vlt11.message, cause: e, stack: st);
    }
  }

  /// vault_init — 返回 0=成功,8 位错误码=失败
  static int init(Uint8List vaultBin) {
    _ensure();
    final ptr = malloc<Uint8>(vaultBin.length);
    try {
      ptr.asTypedList(vaultBin.length).setAll(0, vaultBin);
      return _init(ptr, vaultBin.length);
    } catch (e, st) {
      throw AppError(Ec.vlt10.code, Ec.vlt10.message, cause: e, stack: st);
    } finally {
      malloc.free(ptr);
    }
  }

  /// vault_set_master — 返回 0=成功,8 位错误码=失败
  static int setMaster(Uint8List key) {
    _ensure();
    final ptr = malloc<Uint8>(key.length);
    try {
      ptr.asTypedList(key.length).setAll(0, key);
      return _setMaster(ptr, key.length);
    } catch (e, st) {
      throw AppError(Ec.vlt10.code, Ec.vlt10.message, cause: e, stack: st);
    } finally {
      ptr.asTypedList(key.length).fillRange(0, key.length, 0);
      malloc.free(ptr);
    }
  }

  /// 读 C 端字符串;返回 (值, 错误码);错误码 0=成功,8 位=失败
  static (String?, int) getEndpoint() => _readStr(_get);
  static (String?, int) getApiKey() => _readStr(_getKey);

  static (String?, int) _readStr(int Function(Pointer<Uint8>, int) f) {
    _ensure();
    final buf = malloc<Uint8>(1024);
    try {
      final n = f(buf, 1024);
      if (n == 0) {
        // n=0 可能是真"空字符串",也可能是错误码
        // 错误码是 8 位 10+ 进制数,空字符串返回 0
        return (null, 0);
      }
      if (n < 0 || n >= 100000000) {
        // 错误码(8 位)
        return (null, n);
      }
      // 成功:返回长度 n,需读 n 字节
      var len = n;
      // 找 null 终止
      while (len < 1024 && buf[len] != 0) len++;
      final bytes = Uint8List(len);
      for (var i = 0; i < len; i++) bytes[i] = buf[i];
      return (String.fromCharCodes(bytes), 0);
    } catch (e, st) {
      throw AppError(Ec.vlt12.code, Ec.vlt12.message, cause: e, stack: st);
    } finally {
      malloc.free(buf);
    }
  }

  static int wipe() {
    _ensure();
    try {
      _wipe();
      return 0;
    } catch (e, st) {
      throw AppError(Ec.vlt00.code, Ec.vlt00.message, cause: e, stack: st);
    }
  }
}
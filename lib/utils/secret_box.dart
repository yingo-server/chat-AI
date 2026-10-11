import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 简易端点/密钥混淆:
/// - 用 SHA-256(安装时随机生成的盐 + 设备特征)做密钥
/// - 明文 XOR 密钥后 base64
/// - 不防专业逆向,但防 grep / 防 build artifact 文本扫描
class SecretBox {
  /// 用 [passphrase] 加密 [plaintext] → base64
  static String encrypt(String plaintext, String passphrase) {
    final key = _deriveKey(passphrase);
    final bytes = utf8.encode(plaintext);
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ key[i % key.length];
    }
    return base64Encode(out);
  }

  /// 解密(失败时返回空字符串,绝不抛出)
  static String decrypt(String cipher, String passphrase) {
    try {
      final key = _deriveKey(passphrase);
      final raw = base64Decode(cipher);
      final out = Uint8List(raw.length);
      for (var i = 0; i < raw.length; i++) {
        out[i] = raw[i] ^ key[i % key.length];
      }
      return utf8.decode(out);
    } catch (_) {
      return '';
    }
  }

  /// 派生 32 字节密钥
  static Uint8List _deriveKey(String passphrase) {
    final digest = sha256.convert(utf8.encode('chat-ai-secret:$passphrase'));
    return Uint8List.fromList(digest.bytes);
  }
}

/// 配置中可加密的字段约定:
/// - 明文:字符串
/// - 密文:`{ "e": "<base64>", "k": "<passphrase>" }`
/// 解包时若检测到这种结构,自动解密;
/// 兼容旧明文(用于首次启动时检测)
class SecretField {
  final String plaintext;
  const SecretField(this.plaintext);

  factory SecretField.fromJson(dynamic v, {String fallbackSecret = ''}) {
    if (v is String) return SecretField(v);
    if (v is Map &&
        v['e'] is String &&
        v['k'] is String &&
        (v['e'] as String).isNotEmpty) {
      final pt = SecretBox.decrypt(v['e'] as String, v['k'] as String);
      if (pt.isNotEmpty) return SecretField(pt);
    }
    return const SecretField('');
  }

  bool get isEmpty => plaintext.isEmpty;

  /// 输出 JSON 时: 若 [passphrase] 非空且 plaintext 非空,返回密文;
  /// 否则返回明文字符串(便于兼容旧版)。
  Object toJsonValue(String passphrase) {
    if (plaintext.isEmpty) return '';
    if (passphrase.isEmpty) return plaintext;
    return {
      'e': SecretBox.encrypt(plaintext, passphrase),
      'k': passphrase,
    };
  }
}
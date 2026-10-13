// encrypt_secrets.dart
// 用 master key 把 endpoint + apiKey 加密成 vault.bin
// master key 来自 --dart-define=VAULT_MASTER_KEY (32 字节 hex)
//
// vault.bin 格式:
//   [4 bytes]  magic "VLT1"
//   [16 bytes] nonce
//   [N bytes]  ciphertext(URL)  — AES-256-CTR
//   [4 bytes]  SEP = 0xFF 0xFE 0xFD 0xFC
//   [M bytes]  ciphertext(KEY)  — AES-256-CTR, nonce2 = nonce XOR 0xA5
//   [32 bytes] SHA256(master_key) — 完整性校验
//
// 用法:
//   dart run tools/encrypt_secrets.dart \
//     --endpoint=URL --key=KEY --master=HEX64 --out=assets/vault.bin

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  String? endpoint, key, masterHex, out;
  for (final a in args) {
    if (a.startsWith('--endpoint=')) endpoint = a.substring(11);
    if (a.startsWith('--key=')) key = a.substring(6);
    if (a.startsWith('--master=')) masterHex = a.substring(9);
    if (a.startsWith('--out=')) out = a.substring(6);
  }
  if (endpoint == null || key == null || masterHex == null || out == null) {
    stderr.writeln('usage: --endpoint=URL --key=KEY --master=HEX64 --out=PATH');
    exit(2);
  }

  final master = _hexDecode(masterHex);
  if (master.length != 32) {
    stderr.writeln('master key must be 32 bytes (64 hex chars)');
    exit(2);
  }

  // 生成 16 字节 nonce
  final rnd = Random.secure();
  final nonce = Uint8List(16);
  for (var i = 0; i < 16; i++) nonce[i] = rnd.nextInt(256);

  // AES-256-CTR 加密 URL
  final urlCt = _aesCtrXcrypt(master, nonce, utf8.encode(endpoint));
  final nonce2 = Uint8List.fromList(nonce);
  nonce2[0] ^= 0xA5;
  final keyCt = _aesCtrXcrypt(master, nonce2, utf8.encode(key));

  // 拼装
  final sep = [0xFF, 0xFE, 0xFD, 0xFC];
  final body = BytesBuilder()
    ..add(utf8.encode('VLT1'))
    ..add(nonce)
    ..add(urlCt)
    ..add(sep)
    ..add(keyCt);
  final bin = body.toBytes();

  // 完整性:master 自身的 SHA256
  final digest = sha256.convert(master).bytes;

  final outBytes = Uint8List.fromList([...bin, ...digest]);
  File(out).writeAsBytesSync(outBytes);
  stdout.writeln('wrote ${outBytes.length} bytes to $out');
}

// ==================== AES-256 + CTR(简化实现,与 C++ 兼容)====================

List<int> _aesCtrXcrypt(
    List<int> key, List<int> nonce, List<int> input) {
  final out = Uint8List(input.length);
  final ctx = _Aes256();
  ctx.keyExpand(key);
  final ctr = Uint8List.fromList(nonce);
  final ks = Uint8List(16);
  var off = 0;
  while (off < input.length) {
    ctx.encryptBlock(ctr, ks);
    final n = (input.length - off) < 16 ? (input.length - off) : 16;
    for (var i = 0; i < n; i++) {
      out[off + i] = input[off + i] ^ ks[i];
    }
    off += n;
    // increment_be
    for (var i = 15; i >= 0; i--) {
      if (++ctr[i] != 0) break;
    }
  }
  return out;
}

List<int> _hexDecode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}

class _Aes256 {
  final List<int> _rk = List<int>.filled(60, 0);
  int _rounds = 14;

  static const _sbox = <int>[
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
  ];
  static const _rcon = <int>[0, 1, 2, 4, 8, 16, 32, 64, 128, 27, 54, 108, 216, 171, 77];

  void keyExpand(List<int> key) {
    for (var i = 0; i < 8; i++) {
      _rk[i] = (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }
    var i = 8;
    while (i < 60) {
      var t = _rk[i - 1];
      if (i % 8 == 0) {
        t = ((_sbox[(t >> 16) & 0xff] << 24) |
                (_sbox[(t >> 8) & 0xff] << 16) |
                (_sbox[t & 0xff] << 8) |
                _sbox[(t >> 24) & 0xff]) ^
            ((_rcon[i ~/ 8]) << 24);
      } else if (i % 8 == 4) {
        t = (_sbox[(t >> 24) & 0xff] << 24) |
            (_sbox[(t >> 16) & 0xff] << 16) |
            (_sbox[(t >> 8) & 0xff] << 8) |
            _sbox[t & 0xff];
      }
      _rk[i] = _rk[i - 8] ^ t;
      i++;
    }
  }

  void encryptBlock(List<int> input, List<int> output) {
    final s = List<int>.from(input);
    _addRoundKey(s, 0);
    for (var r = 1; r < _rounds; r++) {
      _subBytes(s);
      _shiftRows(s);
      _mixColumns(s);
      _addRoundKey(s, r * 4);
    }
    _subBytes(s);
    _shiftRows(s);
    _addRoundKey(s, _rounds * 4);
    for (var i = 0; i < 16; i++) output[i] = s[i];
  }

  void _subBytes(List<int> s) {
    for (var i = 0; i < 16; i++) s[i] = _sbox[s[i]];
  }

  void _shiftRows(List<int> s) {
    var t;
    t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
    t = s[2]; s[2] = s[10]; s[10] = t;
    t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;
  }

  int _xtime(int x) => ((x << 1) ^ (((x >> 7) & 1) * 0x1b)) & 0xff;

  void _mixColumns(List<int> s) {
    for (var i = 0; i < 4; i++) {
      final a = s[4 * i], b = s[4 * i + 1], c = s[4 * i + 2], d = s[4 * i + 3];
      final t = a ^ b ^ c ^ d;
      s[4 * i] ^= t ^ _xtime(a ^ b);
      s[4 * i + 1] ^= t ^ _xtime(b ^ c);
      s[4 * i + 2] ^= t ^ _xtime(c ^ d);
      s[4 * i + 3] ^= t ^ _xtime(d ^ a);
    }
  }

  void _addRoundKey(List<int> s, int off) {
    for (var i = 0; i < 4; i++) {
      s[4 * i] ^= (_rk[off + i] >> 24) & 0xff;
      s[4 * i + 1] ^= (_rk[off + i] >> 16) & 0xff;
      s[4 * i + 2] ^= (_rk[off + i] >> 8) & 0xff;
      s[4 * i + 3] ^= _rk[off + i] & 0xff;
    }
  }
}
// encrypt_secrets.dart
// 加密 endpoint + key 到 vault.bin
// 算法: SHA256(master || salt || counter) 作为 keystream,plaintext XOR keystream
// 与 C++ 端 vault.cpp 100% 一致

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

  // 16 字节 salt
  final rnd = Random.secure();
  final salt = Uint8List(16);
  for (var i = 0; i < 16; i++) salt[i] = rnd.nextInt(256);

  // 加密 URL
  final urlBytes = utf8.encode(endpoint);
  final urlCt = _xorCrypt(master, salt, urlBytes);

  // KEY 用 salt XOR 0xA5
  final salt2 = Uint8List.fromList(salt);
  salt2[0] ^= 0xA5;
  final keyCt = _xorCrypt(master, salt2, utf8.encode(key));

  // 拼装
  const sep = [0xFF, 0xFE, 0xFD, 0xFC];
  final body = BytesBuilder()
    ..add(utf8.encode('VLT1'))
    ..add(salt)
    ..add(urlCt)
    ..add(sep)
    ..add(keyCt);
  final bin = body.toBytes();

  // 末尾 32 字节 = SHA256(master)(校验用)
  final digest = sha256.convert(master).bytes;

  final outBytes = Uint8List.fromList([...bin, ...digest]);
  File(out).writeAsBytesSync(outBytes);
  stdout.writeln('wrote ${outBytes.length} bytes to $out');

  // 自检:用同样的 master 重新解密,确认能还原出明文
  final verify = _xorCrypt(master, salt, urlCt);
  if (utf8.decode(verify) != endpoint) {
    stderr.writeln('SELF-CHECK FAILED: decrypt mismatch!');
    exit(1);
  }
  final verify2 = _xorCrypt(master, salt2, keyCt);
  if (utf8.decode(verify2) != key) {
    stderr.writeln('SELF-CHECK FAILED: key decrypt mismatch!');
    exit(1);
  }
  stdout.writeln('self-check passed');
}

// XOR with keystream derived from SHA256(master || salt || counter)
List<int> _xorCrypt(List<int> master, List<int> salt, List<int> input) {
  final out = Uint8List(input.length);
  var off = 0;
  var cursor = 0;
  while (off < input.length) {
    final hash = _keystreamBlock(master, salt, cursor);
    final take = (input.length - off) < 32 ? (input.length - off) : 32;
    for (var i = 0; i < take; i++) {
      out[off + i] = input[off + i] ^ hash[i];
    }
    off += take;
    cursor++;
  }
  return out;
}

Uint8List _keystreamBlock(List<int> master, List<int> salt, int counter) {
  final h = AccumulatorSink<Digest>();
  final sha = sha256.startChunkedConversion(h);
  sha.add(master);
  sha.add(salt);
  // counter as 8 bytes big-endian
  final ctr = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    ctr[7 - i] = (counter >> (i * 8)) & 0xff;
  }
  sha.add(ctr);
  sha.close();
  return Uint8List.fromList(h.events.single.bytes);
}

List<int> _hexDecode(String s) {
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    out.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return out;
}
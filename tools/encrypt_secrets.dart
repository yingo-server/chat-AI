// tools/encrypt_secrets.dart — 纯 Dart CLI 工具,不引用 Flutter
// 加密 endpoint + key 到 vault.bin
// SHA256(master || salt || counter) 作为 keystream,plaintext XOR keystream
// 与 C++ 端 vault.cpp 100% 一致
// 仅抛 AppError(8 位错误码)

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
  encryptAndWrite(
    endpoint: endpoint,
    key: key,
    masterHex: masterHex,
    outPath: out,
  );
}

void encryptAndWrite({
  required String endpoint,
  required String key,
  required String masterHex,
  required String outPath,
}) {
  Uint8List master;
  try {
    master = Uint8List.fromList(_hexDecode(masterHex));
  } catch (e) {
    stderr.writeln('hex decode failed: $e');
    exit(2);
  }
  if (master.length != 32) {
    stderr.writeln('master must be 32 bytes');
    exit(2);
  }

  final rnd = Random.secure();
  final salt = Uint8List(16);
  for (var i = 0; i < 16; i++) salt[i] = rnd.nextInt(256);

  final urlBytes = utf8.encode(endpoint);
  final urlCt = _xorCrypt(master, salt, urlBytes);

  final salt2 = Uint8List.fromList(salt);
  salt2[0] ^= 0xA5;
  final keyCt = _xorCrypt(master, salt2, utf8.encode(key));

  const sep = [0xFF, 0xFE, 0xFD, 0xFC];
  final body = BytesBuilder()
    ..add(utf8.encode('VLT1'))
    ..add(salt)
    ..add(urlCt)
    ..add(sep)
    ..add(keyCt);
  final bin = body.toBytes();

  // trailer = SHA256(master || salt || url_ct || SEP || key_ct) —— 与 vault.cpp 一致
  final digest = sha256.convert(<int>[...master, ...bin]).bytes;

  final outBytes = Uint8List.fromList([...bin, ...digest]);
  try {
    File(outPath).writeAsBytesSync(outBytes);
  } catch (e) {
    stderr.writeln('write failed: $e');
    exit(2);
  }
  stdout.writeln('wrote ${outBytes.length} bytes to $outPath');

  // 自检
  final verify = _xorCrypt(master, salt, urlCt);
  if (utf8.decode(verify) != endpoint) {
    stderr.writeln('SELF-CHECK FAILED: URL mismatch');
    exit(2);
  }
  final verify2 = _xorCrypt(master, salt2, keyCt);
  if (utf8.decode(verify2) != key) {
    stderr.writeln('SELF-CHECK FAILED: KEY mismatch');
    exit(2);
  }
  stdout.writeln('self-check passed');
}

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
  final ctr = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    ctr[7 - i] = (counter >> (i * 8)) & 0xff;
  }
  final buf = Uint8List.fromList([...master, ...salt, ...ctr]);
  final digest = sha256.convert(buf);
  return Uint8List.fromList(digest.bytes);
}

List<int> _hexDecode(String s) {
  if (s.length % 2 != 0) {
    throw 'odd length';
  }
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    final v = int.tryParse(s.substring(i, i + 2), radix: 16);
    if (v == null) throw 'bad hex at $i';
    out.add(v);
  }
  return out;
}
// encrypt_secrets.dart
// 加密 endpoint + key 到 vault.bin
// SHA256(master || salt || counter) 作为 keystream,plaintext XOR keystream
// 与 C++ 端 vault.cpp 100% 一致
// 所有函数抛 AppError(8 位错误码)

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../lib/utils/error_code.dart';

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
    throw AppError(Ec.bd00.code, Ec.bd00.message);
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
    master = _hexDecode(masterHex);
  } catch (e, st) {
    throw AppError(Ec.bd02.code, Ec.bd02.message, cause: e, stack: st);
  }
  if (master.length != 32) {
    throw AppError(Ec.bd01.code, Ec.bd01.message);
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

  final digest = sha256.convert(master).bytes;

  final outBytes = Uint8List.fromList([...bin, ...digest]);
  try {
    File(outPath).writeAsBytesSync(outBytes);
  } catch (e, st) {
    throw AppError(Ec.bd03.code, Ec.bd03.message, cause: e, stack: st);
  }
  stdout.writeln('wrote ${outBytes.length} bytes to $outPath');

  // 自检
  final verify = _xorCrypt(master, salt, urlCt);
  String verifyStr;
  try {
    verifyStr = utf8.decode(verify);
  } catch (e, st) {
    throw AppError(Ec.bd06.code, Ec.bd06.message, cause: e, stack: st);
  }
  if (verifyStr != endpoint) {
    throw AppError(Ec.bd04.code, Ec.bd04.message);
  }
  final verify2 = _xorCrypt(master, salt2, keyCt);
  if (utf8.decode(verify2) != key) {
    throw AppError(Ec.bd05.code, Ec.bd05.message);
  }
  stdout.writeln('self-check passed');
}

List<int> _xorCrypt(List<int> master, List<int> salt, List<int> input) {
  try {
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
  } catch (e, st) {
    throw AppError(Ec.bd07.code, Ec.bd07.message, cause: e, stack: st);
  }
}

Uint8List _keystreamBlock(List<int> master, List<int> salt, int counter) {
  try {
    final h = AccumulatorSink<Digest>();
    final sha = sha256.startChunkedConversion(h);
    sha.add(master);
    sha.add(salt);
    final ctr = Uint8List(8);
    for (var i = 7; i >= 0; i--) {
      ctr[7 - i] = (counter >> (i * 8)) & 0xff;
    }
    sha.add(ctr);
    sha.close();
    return Uint8List.fromList(h.events.single.bytes);
  } catch (e, st) {
    throw AppError(Ec.bd06.code, Ec.bd06.message, cause: e, stack: st);
  }
}

List<int> _hexDecode(String s) {
  if (s.length % 2 != 0) {
    throw AppError(Ec.bd02.code, '${Ec.bd02.message} (odd length)');
  }
  final out = <int>[];
  for (var i = 0; i < s.length; i += 2) {
    final chunk = s.substring(i, i + 2);
    final v = int.tryParse(chunk, radix: 16);
    if (v == null) {
      throw AppError(Ec.bd02.code, '${Ec.bd02.message} (bad hex at $i)');
    }
    out.add(v);
  }
  return out;
}
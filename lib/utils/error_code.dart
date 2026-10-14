/// 8 位错误码系统
///
/// 格式:MM FF FF FF
///   MM (2 位) — 模块标识
///   FFFFFF (6 位) — 功能标识
///
/// 模块映射:
///   10 main         — main() / 启动流程
///   11 config       — config.json 存储
///   12 vault        — Vault FFI / 解密
///   13 db           — SQLite 持久化
///   14 llm          — LLM HTTP/SSE
///   15 chat         — ChatService 业务
///   16 screen       — 屏幕
///   17 widget       — 组件
///   18 export       — 导出
///   19 theme        — 主题
///   20 model        — 数据模型
///   21 platform     — 平台(图片/文件)
///   22 util         — 工具
///   23 build        — 构建/工具脚本
///   30 native       — C++ 原生层
///
/// 每个函数失败返回 [ErrCode],成功 0。
/// 异常被包装成 [AppError],内置 code + message + stack。
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// 错误码构造
class ErrCode {
  final int code;
  final String message;
  const ErrCode(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}

/// AppError — 携带错误码的异常
class AppError implements Exception {
  final int code;
  final String message;
  final Object? cause;
  final StackTrace? stack;
  const AppError(this.code, this.message, {this.cause, this.stack});

  @override
  String toString() {
    final c = cause != null ? ' [cause: $cause]' : '';
    return 'AppError($code): $message$c';
  }
}

/// 错误码定义(每个函数一个)
/// 格式:MM FF FF FF
class Ec {
  // 10 — main
  static const main00 = ErrCode(10000000, 'main: unexpected');
  static const main01 = ErrCode(10000001, 'main: SystemChrome.setPreferredOrientations failed');
  static const main02 = ErrCode(10000002, 'main: ConfigStore.load failed');
  static const main03 = ErrCode(10000003, 'main: vault.init failed');
  static const main04 = ErrCode(10000004, 'main: AppConfig construction failed');
  static const main05 = ErrCode(10000005, 'main: MaterialApp build failed');

  // 11 — config
  static const cfg00 = ErrCode(11000000, 'config: file read failed');
  static const cfg01 = ErrCode(11000001, 'config: file write failed');
  static const cfg02 = ErrCode(11000002, 'config: JSON parse failed');
  static const cfg03 = ErrCode(11000003, 'config: AppConfig.fromJson failed');
  static const cfg04 = ErrCode(11000004, 'config: UserPrefs.fromJson failed');
  static const cfg05 = ErrCode(11000005, 'config: passphrase generate failed');
  static const cfg06 = ErrCode(11000006, 'config: secure storage read failed');
  static const cfg07 = ErrCode(11000007, 'config: secure storage write failed');
  static const cfg08 = ErrCode(11000008, 'config: salt file write failed');
  static const cfg09 = ErrCode(11000009, 'config: missing file');

  // 12 — vault
  static const vlt00 = ErrCode(12000000, 'vault: libvault.so load failed');
  static const vlt01 = ErrCode(12000001, 'vault: master key length invalid');
  static const vlt02 = ErrCode(12000002, 'vault: master key missing');
  static const vlt03 = ErrCode(12000003, 'vault: secure storage read failed');
  static const vlt04 = ErrCode(12000004, 'vault: secure storage write failed');
  static const vlt05 = ErrCode(12000005, 'vault: vault.bin asset load failed');
  static const vlt06 = ErrCode(12000006, 'vault: vault_init native call failed');
  static const vlt07 = ErrCode(12000007, 'vault: vault_set_master native call failed');
  static const vlt08 = ErrCode(12000008, 'vault: get_endpoint returned null/empty');
  static const vlt09 = ErrCode(12000009, 'vault: get_api_key returned null/empty');
  static const vlt10 = ErrCode(12000010, 'vault: buffer allocate failed');
  static const vlt11 = ErrCode(12000011, 'vault: native function lookup failed');
  static const vlt12 = ErrCode(12000012, 'vault: FFI read string null termination lost');

  // 13 — database
  static const db00 = ErrCode(13000000, 'db: open failed');
  static const db01 = ErrCode(13000001, 'db: insert chat failed');
  static const db02 = ErrCode(13000002, 'db: update chat failed');
  static const db03 = ErrCode(13000003, 'db: delete chat failed');
  static const db04 = ErrCode(13000004, 'db: list chats failed');
  static const db05 = ErrCode(13000005, 'db: get chat failed');
  static const db06 = ErrCode(13000006, 'db: insert message failed');
  static const db07 = ErrCode(13000007, 'db: list messages failed');
  static const db08 = ErrCode(13000008, 'db: delete messages for chat failed');
  static const db09 = ErrCode(13000009, 'db: mark messages compressed failed');
  static const db10 = ErrCode(13000010, 'db: update message content failed');
  static const db11 = ErrCode(13000011, 'db: touch chat failed');

  // 14 — LLM
  static const llm00 = ErrCode(14000000, 'llm: stream open failed');
  static const llm01 = ErrCode(14000001, 'llm: HTTP non-200');
  static const llm02 = ErrCode(14000002, 'llm: stream read error');
  static const llm03 = ErrCode(14000003, 'llm: stream closed prematurely');
  static const llm04 = ErrCode(14000004, 'llm: JSON parse error');
  static const llm05 = ErrCode(14000005, 'llm: timeout');
  static const llm06 = ErrCode(14000006, 'llm: response missing content field');
  static const llm07 = ErrCode(14000007, 'llm: non-stream chat failed');
  static const llm08 = ErrCode(14000008, 'llm: connection refused');
  static const llm09 = ErrCode(14000009, 'llm: TLS handshake failed');

  // 15 — chat service
  static const ch00 = ErrCode(15000000, 'chat: insert user msg failed');
  static const ch01 = ErrCode(15000001, 'chat: buildPrompt failed');
  static const ch02 = ErrCode(15000002, 'chat: insert assistant msg failed');
  static const ch03 = ErrCode(15000003, 'chat: touch chat failed');
  static const ch04 = ErrCode(15000004, 'chat: compress trigger failed');
  static const ch05 = ErrCode(15000005, 'chat: compress summary empty');
  static const ch06 = ErrCode(15000006, 'chat: stream consumed error');
  static const ch07 = ErrCode(15000007, 'chat: history read failed');
  static const ch08 = ErrCode(15000008, 'chat: persist user msg failed');

  // 16 — screens
  static const sc00 = ErrCode(16000000, 'screen: chat open failed');
  static const sc01 = ErrCode(16000001, 'screen: new chat dialog failed');
  static const sc02 = ErrCode(16000002, 'screen: delete chat confirm failed');
  static const sc03 = ErrCode(16000003, 'screen: rename chat failed');
  static const sc04 = ErrCode(16000004, 'screen: input dialog failed');
  static const sc05 = ErrCode(16000005, 'screen: list refresh failed');
  static const sc06 = ErrCode(16000006, 'screen: export sheet failed');
  static const sc07 = ErrCode(16000007, 'screen: prompt status sheet failed');
  static const sc08 = ErrCode(16000008, 'screen: theme apply failed');
  static const sc09 = ErrCode(16000009, 'screen: settings prefs save failed');
  static const sc10 = ErrCode(16000010, 'screen: image pick failed');
  static const sc11 = ErrCode(16000011, 'screen: file pick failed');
  static const sc12 = ErrCode(16000012, 'screen: attachment add failed');
  static const sc13 = ErrCode(16000013, 'screen: send stream failed');
  static const sc14 = ErrCode(16000014, 'screen: stop failed');
  static const sc15 = ErrCode(16000015, 'screen: bootstrap failed');
  static const sc16 = ErrCode(16000016, 'screen: scroll failed');
  static const sc17 = ErrCode(16000017, 'screen: textfield submit failed');

  // 17 — widgets
  static const wd00 = ErrCode(17000000, 'widget: bubble build failed');
  static const wd01 = ErrCode(17000001, 'widget: streaming bubble build failed');
  static const wd02 = ErrCode(17000002, 'widget: typing indicator build failed');
  static const wd03 = ErrCode(17000003, 'widget: export sheet build failed');
  static const wd04 = ErrCode(17000004, 'widget: prompt status build failed');
  static const wd05 = ErrCode(17000005, 'widget: snackbar show failed');
  static const wd06 = ErrCode(17000006, 'widget: dialog show failed');

  // 18 — export
  static const ex00 = ErrCode(18000000, 'export: temp dir get failed');
  static const ex01 = ErrCode(18000001, 'export: file write failed');
  static const ex02 = ErrCode(18000002, 'export: share failed');
  static const ex03 = ErrCode(18000003, 'export: invalid format');
  static const ex04 = ErrCode(18000004, 'export: title sanitize failed');
  static const ex05 = ErrCode(18000005, 'export: messages empty');

  // 19 — theme
  static const th00 = ErrCode(19000000, 'theme: scheme from seed failed');
  static const th01 = ErrCode(19000001, 'theme: textTheme copy failed');

  // 20 — model
  static const md00 = ErrCode(20000000, 'model: Chat.fromMap failed');
  static const md01 = ErrCode(20000001, 'model: Message.fromMap failed');
  static const md02 = ErrCode(20000002, 'model: AppConfig.fromJson failed');
  static const md03 = ErrCode(20000003, 'model: UserPrefs.fromJson failed');
  static const md04 = ErrCode(20000004, 'model: copyWith failed');
  static const md05 = ErrCode(20000005, 'model: AiConfig.fromVault failed');
  static const md06 = ErrCode(20000006, 'model: invalid chat id');
  static const md07 = ErrCode(20000007, 'model: invalid message id');
  static const md08 = ErrCode(20000008, 'model: toJson failed');

  // 21 — platform
  static const pf00 = ErrCode(21000000, 'platform: image picker error');
  static const pf01 = ErrCode(21000001, 'platform: file picker error');
  static const pf02 = ErrCode(21000002, 'platform: file not found');
  static const pf03 = ErrCode(21000003, 'platform: share dialog dismissed');
  static const pf04 = ErrCode(21000004, 'platform: clipboard set failed');

  // 22 — util
  static const ut00 = ErrCode(22000000, 'util: showSnack failed');
  static const ut01 = ErrCode(22000001, 'util: confirmDialog failed');
  static const ut02 = ErrCode(22000002, 'util: inputDialog failed');
  static const ut03 = ErrCode(22000003, 'util: intl format failed');
  static const ut04 = ErrCode(22000004, 'util: date parse failed');

  // 23 — build / tool
  static const bd00 = ErrCode(23000000, 'build: missing args');
  static const bd01 = ErrCode(23000001, 'build: bad master key length');
  static const bd02 = ErrCode(23000002, 'build: hex decode failed');
  static const bd03 = ErrCode(23000003, 'build: write file failed');
  static const bd04 = ErrCode(23000004, 'build: self-check URL mismatch');
  static const bd05 = ErrCode(23000005, 'build: self-check key mismatch');
  static const bd06 = ErrCode(23000006, 'build: SHA256 init failed');
  static const bd07 = ErrCode(23000007, 'build: random generation failed');

  // 30 — C++ native
  // (由 vault.cpp 返回,值定义在 vault_ffi.dart 中转)
}

/// 把任意异常包装成 AppError;若 [ec] 为 null 则从 cause 推断
AppError wrap(ErrCode ec, Object cause, [StackTrace? stack]) =>
    AppError(ec.code, ec.message, cause: cause, stack: stack);

/// 捕获异步错误转 AppError
Future<T> guard<T>(ErrCode ec, Future<T> Function() body) async {
  try {
    return await body();
  } on AppError {
    rethrow;
  } catch (e, st) {
    throw wrap(ec, e, st);
  }
}

/// 同步版本
T guardSync<T>(ErrCode ec, T Function() body) {
  try {
    return body();
  } on AppError {
    rethrow;
  } catch (e, st) {
    throw wrap(ec, e, st);
  }
}

/// 把任意错误码转人类可读消息(供 SnackBar / dialog)
String ecMessage(Object e) {
  if (e is AppError) return e.toString();
  if (e is PlatformException) return '平台错误: ${e.code} ${e.message ?? ""}';
  if (e is SocketException) return '网络错误: ${e.message}';
  if (e is HttpException) return 'HTTP 错误: ${e.message}';
  if (e is TimeoutException) return '操作超时';
  if (e is FormatException) return '数据格式错误: ${e.message}';
  if (e is Error) return e.toString();
  return e.toString();
}
/// 8 位错误码系统(可选使用,不影响现有代码)
///
/// 格式:MM FF FF FF
///   MM (2 位) — 模块标识
///   FFFFFF (6 位) — 功能标识
///
/// 模块映射:
///   10 main         11 config       12 vault        13 db
///   14 llm          15 chat         16 screen       17 widget
///   18 export       19 theme        20 model        21 platform
///   22 util         30 native
///
/// 这是一个**库**(工具类),任何业务代码都可以用 `throw AppError(Ec.xx00.code, ...)` 抛错。
/// 现有代码不需要改;新代码可以选择性使用。
library;

class ErrCode {
  final int code;
  final String message;
  const ErrCode(this.code, this.message);
  @override
  String toString() => '[$code] $message';
}

/// 携带 8 位错误码的异常
class AppError implements Exception {
  final int code;
  final String message;
  final Object? cause;
  final StackTrace? stack;
  const AppError(this.code, this.message, {this.cause, this.stack});
  @override
  String toString() => 'AppError($code): $message${cause != null ? ' [$cause]' : ''}';
}

/// 错误码字典(只列常用的,够业务用)
class Ec {
  // 10 — main
  static const main00 = ErrCode(10000000, 'main: unexpected');
  static const main01 = ErrCode(10000001, 'main: orient set failed');
  static const main02 = ErrCode(10000002, 'main: config load failed');
  static const main03 = ErrCode(10000003, 'main: vault init failed');
  static const main04 = ErrCode(10000004, 'main: AppConfig build failed');
  static const main05 = ErrCode(10000005, 'main: MaterialApp build failed');

  // 11 — config
  static const cfg00 = ErrCode(11000000, 'config: read failed');
  static const cfg01 = ErrCode(11000001, 'config: write failed');
  static const cfg02 = ErrCode(11000002, 'config: parse failed');
  static const cfg03 = ErrCode(11000003, 'config: file missing');

  // 12 — vault
  static const vlt00 = ErrCode(12000000, 'vault: lib load failed');
  static const vlt01 = ErrCode(12000001, 'vault: master invalid');
  static const vlt02 = ErrCode(12000002, 'vault: not initialized');
  static const vlt03 = ErrCode(12000003, 'vault: secure read failed');
  static const vlt04 = ErrCode(12000004, 'vault: secure write failed');
  static const vlt05 = ErrCode(12000005, 'vault: asset load failed');
  static const vlt06 = ErrCode(12000006, 'vault: init failed');
  static const vlt08 = ErrCode(12000008, 'vault: endpoint empty');
  static const vlt09 = ErrCode(12000009, 'vault: key empty');

  // 13 — db
  static const db00 = ErrCode(13000000, 'db: open failed');
  static const db01 = ErrCode(13000001, 'db: insert chat failed');
  static const db02 = ErrCode(13000002, 'db: update chat failed');
  static const db03 = ErrCode(13000003, 'db: delete chat failed');
  static const db04 = ErrCode(13000004, 'db: list chats failed');
  static const db05 = ErrCode(13000005, 'db: get chat failed');
  static const db06 = ErrCode(13000006, 'db: insert message failed');
  static const db07 = ErrCode(13000007, 'db: list messages failed');
  static const db08 = ErrCode(13000008, 'db: delete messages failed');
  static const db09 = ErrCode(13000009, 'db: mark compressed failed');
  static const db10 = ErrCode(13000010, 'db: update content failed');
  static const db11 = ErrCode(13000011, 'db: touch chat failed');

  // 14 — llm
  static const llm00 = ErrCode(14000000, 'llm: stream error');
  static const llm01 = ErrCode(14000001, 'llm: HTTP error');
  static const llm04 = ErrCode(14000004, 'llm: parse error');
  static const llm05 = ErrCode(14000005, 'llm: timeout');
  static const llm06 = ErrCode(14000006, 'llm: missing content');
  static const llm07 = ErrCode(14000007, 'llm: chat failed');
  static const llm08 = ErrCode(14000008, 'llm: connection refused');

  // 15 — chat service
  static const ch00 = ErrCode(15000000, 'chat: insert user failed');
  static const ch01 = ErrCode(15000001, 'chat: buildPrompt failed');
  static const ch02 = ErrCode(15000002, 'chat: insert assistant failed');
  static const ch03 = ErrCode(15000003, 'chat: touch failed');
  static const ch04 = ErrCode(15000004, 'chat: compress failed');
  static const ch05 = ErrCode(15000005, 'chat: summary empty');
  static const ch06 = ErrCode(15000006, 'chat: stream error');
  static const ch07 = ErrCode(15000007, 'chat: read history failed');
  static const ch08 = ErrCode(15000008, 'chat: persist user failed');

  // 16 — screen
  static const sc00 = ErrCode(16000000, 'screen: open chat failed');
  static const sc01 = ErrCode(16000001, 'screen: new chat failed');
  static const sc02 = ErrCode(16000002, 'screen: delete failed');
  static const sc03 = ErrCode(16000003, 'screen: rename failed');
  static const sc05 = ErrCode(16000005, 'screen: refresh failed');
  static const sc06 = ErrCode(16000006, 'screen: export failed');
  static const sc09 = ErrCode(16000009, 'screen: settings open failed');
  static const sc10 = ErrCode(16000010, 'screen: image pick failed');
  static const sc11 = ErrCode(16000011, 'screen: file pick failed');
  static const sc13 = ErrCode(16000013, 'screen: send failed');
  static const sc14 = ErrCode(16000014, 'screen: stop failed');
  static const sc15 = ErrCode(16000015, 'screen: bootstrap failed');
  static const sc16 = ErrCode(16000016, 'screen: scroll failed');
  static const sc17 = ErrCode(16000017, 'screen: submit failed');

  // 17 — widget
  static const wd00 = ErrCode(17000000, 'widget: bubble failed');
  static const wd01 = ErrCode(17000001, 'widget: streaming failed');
  static const wd06 = ErrCode(17000006, 'widget: dialog failed');

  // 18 — export
  static const ex00 = ErrCode(18000000, 'export: tmp dir failed');
  static const ex01 = ErrCode(18000001, 'export: write failed');
  static const ex02 = ErrCode(18000002, 'export: share failed');
  static const ex04 = ErrCode(18000004, 'export: title invalid');
  static const ex05 = ErrCode(18000005, 'export: empty messages');

  // 19 — theme
  static const th00 = ErrCode(19000000, 'theme: scheme failed');

  // 20 — model
  static const md00 = ErrCode(20000000, 'model: Chat fromMap failed');
  static const md01 = ErrCode(20000001, 'model: Message fromMap failed');
  static const md04 = ErrCode(20000004, 'model: copyWith failed');
  static const md06 = ErrCode(20000006, 'model: invalid chat id');
  static const md08 = ErrCode(20000008, 'model: toJson failed');

  // 21 — platform
  static const pf02 = ErrCode(21000002, 'platform: file not found');
  static const pf04 = ErrCode(21000004, 'platform: clipboard set failed');

  // 22 — util
  static const ut00 = ErrCode(22000000, 'util: snack failed');
  static const ut01 = ErrCode(22000001, 'util: confirm dialog failed');
  static const ut02 = ErrCode(22000002, 'util: input dialog failed');

  // 30 — native (C++ 返回码,Dart 端映射)
  static const n01 = ErrCode(30000001, 'native: tampered/rooted');
  static const n02 = ErrCode(30000002, 'native: master not set');
  static const n04 = ErrCode(30000004, 'native: parse failed');
  static const n09 = ErrCode(30000009, 'native: not initialized');
  static const n10 = ErrCode(30000010, 'native: master length invalid');
}

/// 把异常/对象转可读字符串(给 SnackBar 用)
String ecMessage(Object? e) {
  if (e == null) return '未知错误';
  if (e is AppError) return e.toString();
  return e.toString();
}
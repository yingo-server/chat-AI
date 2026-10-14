// tools/error_code.dart — 纯 Dart 错误码(给 encrypt_secrets.dart 用)
// 不引用任何 Flutter 包。

class ErrCode {
  final int code;
  final String message;
  const ErrCode(this.code, this.message);
  @override
  String toString() => '[$code] $message';
}

class Ec {
  // 23 build / tool
  static const bd00 = ErrCode(23000000, 'build: missing args');
  static const bd01 = ErrCode(23000001, 'build: bad master key length');
  static const bd02 = ErrCode(23000002, 'build: hex decode failed');
  static const bd03 = ErrCode(23000003, 'build: write file failed');
  static const bd04 = ErrCode(23000004, 'build: self-check URL mismatch');
  static const bd05 = ErrCode(23000005, 'build: self-check key mismatch');
  static const bd06 = ErrCode(23000006, 'build: SHA256 init failed');
  static const bd07 = ErrCode(23000007, 'build: random generation failed');
}

class AppError implements Exception {
  final int code;
  final String message;
  final Object? cause;
  final StackTrace? stack;
  AppError(this.code, this.message, {this.cause, this.stack});
  @override
  String toString() => 'AppError($code): $message${cause != null ? ' [$cause]' : ''}';
}
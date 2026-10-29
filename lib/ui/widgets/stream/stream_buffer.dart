import 'dart:async';
import 'package:flutter/foundation.dart';

/// 流式输出节流缓冲器(合并:限速 + 上限 100 字抗抖动)
///
/// - **限速**(可调,默认 24 字/秒):以固定速率把已累积字符推给监听者
/// - **上限 100 字**(内部固定,不可配):缓冲超过此值立即清空(防内存膨胀、削减首帧延迟)
/// - 边界:
///   - 上游单次 `add()` 已被节流到不超过上限;
///
/// 用法:上游 SSE 拿到 delta 立即 `add`,UI 通过 `displayed` 实时读取
/// `displayed` 为 `ValueListenable<String>`,新增监听后立即收到当前值。
class StreamBuffer {
  /// 固定缓冲上限(100 字):吸收网络抖动,防止首帧延迟与内存膨胀。
  /// 由应用内部控制,不向用户暴露。
  static const int fixedMaxBuffer = 100;

  StreamBuffer({
    this.charsPerSecond = 24,
    Duration tickInterval = const Duration(milliseconds: 40),
    this.maxBuffer = 100,
  })  : _displayed = ValueNotifier<String>(''),
        _tickInterval = tickInterval;

  /// 内部固定上限,UI 不可改
  final int maxBuffer;
  final Duration _tickInterval;
  final double charsPerSecond;
  final ValueNotifier<String> _displayed;
  ValueListenable<String> get displayed => _displayed;

  final StringBuffer _buffer = StringBuffer();
  double _carry = 0.0;
  Timer? _timer;
  bool _disposed = false;

  void add(String chunk) {
    if (_disposed || chunk.isEmpty) return;
    final over = _buffer.length + chunk.length - maxBuffer;
    if (over >= 0) {
      // 上限策略:先按限速整批推送,剩余以限速释放(保留"平滑"观感)
      // —— 一次性 flush 仍按 charsPerSecond 节流(传入 flush 触发节流链)
      // 这里简化为"立即发送"以保证抖动抗性优先
      _displayed.value = _displayed.value + _buffer.toString() + chunk;
      _buffer.clear();
      _carry = 0.0;
      return;
    }
    _buffer.write(chunk);
    _start();
  }

  void _start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void _tick() {
    if (_disposed) return;
    if (charsPerSecond <= 0) return;
    final want = charsPerSecond * (_tickInterval.inMilliseconds / 1000.0) + _carry;
    final n = want.clamp(1, maxBuffer).toInt();
    if (_buffer.length == 0) {
      // 没有缓冲,关闭定时器,显著降低 CPU
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_buffer.length <= n) {
      _displayed.value = _displayed.value + _buffer.toString();
      _buffer.clear();
      _carry = 0.0;
      _timer?.cancel();
      _timer = null;
    } else {
      final s = _buffer.toString();
      _displayed.value = _displayed.value + s.substring(0, n);
      _buffer
        ..clear()
        ..write(s.substring(n));
      _carry = want - n;
    }
  }

  /// 流结束:冲刷剩余
  Future<void> flush() async {
    if (_disposed) return;
    if (_buffer.isEmpty) return;
    _displayed.value = _displayed.value + _buffer.toString();
    _buffer.clear();
    _carry = 0.0;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _displayed.dispose();
  }
}

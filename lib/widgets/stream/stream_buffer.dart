import 'dart:async';
import 'package:flutter/foundation.dart';

/// 流式节流缓冲器 — 两种互斥模式(构造后不可变):
/// - 缓冲模式: [charsPerSecond]==0 && [maxBuffer]>0 → 累积,长度 ≥ maxBuffer 时一次性放出
/// - 限速模式: [charsPerSecond]>0 && [maxBuffer]==0 → 每 [tickInterval] 用小数累加器
///   按速率释放(支持 4-120 cps 的低速率)
/// - 两者皆为 0 → 直接透传
class StreamBuffer {
  StreamBuffer({
    this.charsPerSecond = 24,
    this.maxBuffer = 50,
    this.tickInterval = const Duration(milliseconds: 40),
  })  : assert(!(charsPerSecond > 0 && maxBuffer > 0),
            'charsPerSecond 与 maxBuffer 互斥,只能有一个 > 0'),
        _displayed = ValueNotifier<String>('') {
    if (charsPerSecond > 0) {
      _timer = Timer.periodic(tickInterval, (_) => _tick());
    }
  }

  final ValueNotifier<String> _displayed;
  ValueListenable<String> get displayed => _displayed;
  String get value => _displayed.value;

  Timer? _timer;
  final StringBuffer _buffer = StringBuffer();

  final double charsPerSecond;
  final int maxBuffer;
  final Duration tickInterval;
  bool _disposed = false;

  /// 小数累加器:低速率(如 4cps * 0.04s = 0.16 字/tick)也能累积后整字放出
  double _carry = 0.0;

  bool get _isSpeedMode => charsPerSecond > 0 && maxBuffer == 0;
  bool get _isBufferMode => charsPerSecond == 0 && maxBuffer > 0;

  void add(String chunk) {
    if (_disposed || chunk.isEmpty) return;

    // 透传模式
    if (!_isSpeedMode && !_isBufferMode) {
      _emit(chunk);
      return;
    }

    _buffer.write(chunk);

    // 仅缓冲模式做阈值泄洪;限速模式(maxBuffer==0)由 tick 节奏控制
    if (_isBufferMode && _buffer.length >= maxBuffer) {
      _emit(_buffer.toString());
      _buffer.clear();
    }
  }

  Future<void> flush() async {
    if (_disposed) return;
    if (_buffer.isEmpty) return;
    _emit(_buffer.toString());
    _buffer.clear();
  }

  void _emit(String s) {
    _displayed.value = _displayed.value + s;
  }

  void _tick() {
    if (_disposed || _buffer.isEmpty) return;
    final secondsPerTick = tickInterval.inMilliseconds / 1000.0;
    // 本 tick 应释放的字符数(含上次余数)
    final want = charsPerSecond * secondsPerTick + _carry;
    var n = want.floor();
    _carry = want - n;
    // 钳制到实际缓冲长度,防止越界;钳掉的量计入 carry
    if (n > _buffer.length) {
      _carry = 0.0;
      n = _buffer.length;
    }
    if (n <= 0) return;
    final s = _buffer.toString();
    _emit(s.substring(0, n));
    _buffer
      ..clear()
      ..write(s.substring(n));
  }

  void reset() {
    if (_disposed) return;
    _buffer.clear();
    _carry = 0.0;
    _displayed.value = '';
  }

  void dispose() {
    if (_disposed) return;
    // 先把未放出的内容冲出去,再取消定时器、销毁 notifier
    if (_buffer.isNotEmpty) {
      _displayed.value = _displayed.value + _buffer.toString();
      _buffer.clear();
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _displayed.dispose();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';

/// 流式节流缓冲器。
///
/// 工作机制:
/// - 上游以任意速度 `add(chunk)` 灌入文本
/// - 内部维护一个 StringBuffer
/// - 每 [tickInterval] 释放约 [charsPerSecond] * tick(秒) 个字符
/// - 当缓冲长度 ≥ [maxBuffer] 时,触发一次性"泄洪"以避免积压
/// - 上游关闭时调用 [flush] 把残余放完
///
/// 暴露 [displayed](ValueListenable<String>)给 UI 用 `ValueListenableBuilder`。
class StreamBuffer {
  StreamBuffer({
    this.charsPerSecond = 24,
    this.maxBuffer = 50,
    this.tickInterval = const Duration(milliseconds: 40),
  }) : _displayed = ValueNotifier<String>('') {
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  final ValueNotifier<String> _displayed;

  /// 当前已对外展示的文本
  ValueListenable<String> get displayed => _displayed;
  String get value => _displayed.value;

  Timer? _timer;
  final StringBuffer _buffer = StringBuffer();

  /// 目标速率,单位:字符/秒
  double charsPerSecond;

  /// 缓冲阈值;超过则触发"泄洪"
  int maxBuffer;

  /// 释放 tick 周期
  Duration tickInterval;

  bool _disposed = false;

  /// 直接灌入增量文本
  void add(String chunk) {
    if (_disposed || chunk.isEmpty) return;
    _buffer.write(chunk);
    if (_buffer.length >= maxBuffer) {
      _emit(_buffer.toString());
      _buffer.clear();
    }
  }

  /// 上游结束时调用:把残余立刻放完
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    _emit(_buffer.toString());
    _buffer.clear();
  }

  void _emit(String s) {
    _displayed.value = _displayed.value + s;
  }

  void _tick() {
    if (_buffer.isEmpty) return;
    final n = (charsPerSecond * (tickInterval.inMilliseconds / 1000.0))
        .ceil()
        .clamp(1, maxBuffer);
    if (_buffer.length <= n) {
      _emit(_buffer.toString());
      _buffer.clear();
    } else {
      final s = _buffer.toString();
      _emit(s.substring(0, n));
      _buffer
        ..clear()
        ..write(s.substring(n));
    }
  }

  /// 重置(新一轮)
  void reset() {
    _buffer.clear();
    _displayed.value = '';
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _displayed.dispose();
  }
}
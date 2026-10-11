import 'dart:async';
import 'package:flutter/foundation.dart';

/// 流式节流缓冲器:
/// - 接收上游 token `add(chunk)`
/// - 内部 StringBuffer
/// - 每 [tickInterval] 释放约 [charsPerSecond] 字
/// - 当缓冲长度 ≥ [maxBuffer] 时,触发一次性"泄洪"
///
/// [charsPerSecond] = 0 → 直接透传(不缓冲,也不限速)
/// [maxBuffer] = 0 → 不主动泄洪,完全由 [charsPerSecond] 控制节奏
class StreamBuffer {
  StreamBuffer({
    this.charsPerSecond = 24,
    this.maxBuffer = 50,
    this.tickInterval = const Duration(milliseconds: 40),
  }) : _displayed = ValueNotifier<String>('') {
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  final ValueNotifier<String> _displayed;
  ValueListenable<String> get displayed => _displayed;
  String get value => _displayed.value;

  Timer? _timer;
  final StringBuffer _buffer = StringBuffer();

  double charsPerSecond;
  int maxBuffer;
  Duration tickInterval;
  bool _disposed = false;

  void add(String chunk) {
    if (_disposed || chunk.isEmpty) return;
    if (charsPerSecond <= 0 && maxBuffer <= 0) {
      // 全开透传
      _emit(chunk);
      return;
    }
    if (charsPerSecond <= 0 && maxBuffer > 0) {
      // 仅缓冲模式:攒到 maxBuffer 一次性放完
      _buffer.write(chunk);
      if (_buffer.length >= maxBuffer) {
        _emit(_buffer.toString());
        _buffer.clear();
      }
      return;
    }
    _buffer.write(chunk);
    if (_buffer.length >= maxBuffer) {
      _emit(_buffer.toString());
      _buffer.clear();
    }
  }

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
    if (charsPerSecond <= 0) return; // 纯缓冲模式不靠 tick 释放
    final n = (charsPerSecond * (tickInterval.inMilliseconds / 1000.0))
        .ceil()
        .clamp(1, 4096);
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
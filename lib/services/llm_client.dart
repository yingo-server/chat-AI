import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';

/// 一条 OpenAI 兼容消息
class ApiMessage {
  final String role;
  final String content;
  const ApiMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// 流式客户端 — 解析 SSE 的 `data: {...}` 帧
class LlmStreamClient {
  final AiConfig config;
  LlmStreamClient(this.config);

  /// 流式调用。每次拿到增量文本时调用 [onDelta]。
  /// 抛错时会通过 [onError];正常结束会调用 [onDone]。
  Stream<LlmEvent> chatStream(List<ApiMessage> messages) {
    final controller = StreamController<LlmEvent>();
    final client = http.Client();

    final body = jsonEncode({
      'model': config.model,
      'temperature': config.temperature,
      'max_tokens': config.maxTokens,
      'stream': true,
      'messages': messages.map((e) => e.toJson()).toList(),
    });

    Future<void> run() async {
      try {
        final req = http.Request('POST', Uri.parse(config.endpoint))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
            'Accept': 'text/event-stream',
          })
          ..body = body;
        final resp = await client.send(req).timeout(
              Duration(seconds: config.requestTimeoutSeconds),
            );
        if (resp.statusCode != 200) {
          final err = await resp.stream.bytesToString();
          controller.addError(
              'HTTP ${resp.statusCode}: ${err.length > 200 ? '${err.substring(0, 200)}…' : err}');
          await controller.close();
          return;
        }

        String buffer = '';
        final decoder = const Utf8Decoder();
        await for (final chunk
            in resp.stream.transform(decoder).transform(const LineSplitter())) {
          if (controller.isClosed) break;
          buffer += chunk;
          // 解析完整 data: 行
          while (true) {
            final idx = buffer.indexOf('\n');
            if (idx < 0) break;
            final line = buffer.substring(0, idx).trim();
            buffer = buffer.substring(idx + 1);
            if (line.isEmpty) continue;
            if (!line.startsWith('data:')) continue;
            final payload = line.substring(5).trim();
            if (payload == '[DONE]') {
              controller.add(const LlmEvent.done());
              await controller.close();
              client.close();
              return;
            }
            try {
              final j = jsonDecode(payload) as Map<String, dynamic>;
              final delta = j['choices']?[0]?['delta']?['content'];
              if (delta is String && delta.isNotEmpty) {
                controller.add(LlmEvent.delta(delta));
              }
              // 可选:提取 usage(非流式末尾才会出现)
              final usage = j['usage'];
              if (usage is Map) {
                controller.add(LlmEvent.usage(usage.cast()));
              }
            } catch (_) {/* 忽略坏帧 */}
          }
        }
        controller.add(const LlmEvent.done());
        await controller.close();
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      } finally {
        client.close();
      }
    }

    run();
    controller.onCancel = () => client.close();
    return controller.stream;
  }

  /// 非流式单次调用(用于压缩)
  Future<String> chatOnce(List<ApiMessage> messages,
      {String? overrideModel, double? temperature}) async {
    final m = overrideModel ?? config.model;
    final t = temperature ?? config.temperature;
    final body = jsonEncode({
      'model': m,
      'temperature': t,
      'max_tokens': config.maxTokens,
      'stream': false,
      'messages': messages.map((e) => e.toJson()).toList(),
    });
    final resp = await http
        .post(
          Uri.parse(config.endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: body,
        )
        .timeout(Duration(seconds: config.requestTimeoutSeconds));
    if (resp.statusCode != 200) {
      throw 'HTTP ${resp.statusCode}: ${resp.body}';
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (j['choices']?[0]?['message']?['content'] as String?) ?? '';
  }
}

class LlmEvent {
  final String? delta;
  final Map<String, dynamic>? usage;
  final bool done;
  const LlmEvent.delta(String this.delta)
      : usage = null,
        done = false;
  const LlmEvent.usage(this.usage) : delta = null, done = false;
  const LlmEvent.done()
      : delta = null,
        usage = null,
        done = true;
}
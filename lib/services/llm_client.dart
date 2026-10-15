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

class _ChatRequest {
  final List<ApiMessage> messages;
  final String? reasoningEffort; // 'low' / 'high' / 'max' / 'none' / null
  const _ChatRequest(this.messages, this.reasoningEffort);
}

/// 流式客户端 — 解析 SSE 的 `data: {...}` 帧
class LlmStreamClient {
  final AiConfig config;
  LlmStreamClient(this.config);

  /// OpenAI 兼容接口的完整 URL:
  /// 端点可能是 base(如 http://host:3000/v1)也可能是完整路径,
  /// 这里统一补全为 .../chat/completions,避免 POST 到 base 得到 404。
  Uri _chatCompletionsUri() {
    var ep = config.endpoint.trim();
    while (ep.endsWith('/')) {
      ep = ep.substring(0, ep.length - 1);
    }
    if (!ep.endsWith('/chat/completions')) {
      ep = '$ep/chat/completions';
    }
    return Uri.parse(ep);
  }

  /// 流式调用。每次拿到增量文本时调用 [onDelta]。
  /// [firstTurn]=true 时,使用 [AiConfig.firstTurnReasoning];否则 [AiConfig.subsequentReasoning]。
  Stream<LlmEvent> chatStream(
    List<ApiMessage> messages, {
    bool firstTurn = false,
  }) {
    final effort = firstTurn
        ? config.firstTurnReasoning
        : config.subsequentReasoning;
    return _streamInternal(messages, reasoningEffort: effort);
  }

  Stream<LlmEvent> _streamInternal(
    List<ApiMessage> messages, {
    String? reasoningEffort,
  }) {
    final controller = StreamController<LlmEvent>();
    final client = http.Client();

    final body = <String, dynamic>{
      'model': config.model,
      'temperature': config.temperature,
      'max_tokens': config.maxTokens,
      'stream': true,
      'messages': messages.map((e) => e.toJson()).toList(),
    };
    if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
      body['reasoning_effort'] = reasoningEffort;
    }

    Future<void> run() async {
      try {
        final req = http.Request('POST', _chatCompletionsUri())
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode(body);
        final resp = await client.send(req).timeout(
              Duration(seconds: config.requestTimeoutSeconds),
            );
        if (resp.statusCode != 200) {
          final err = await resp.stream.bytesToString();
          if (!controller.isClosed) {
            controller.addError(
                'HTTP ${resp.statusCode}: ${err.length > 200 ? '${err.substring(0, 200)}…' : err}');
          }
          await controller.close();
          return;
        }

        // LineSplitter 已按行切分,直接逐行处理,切勿再按 '\n' 累积查找
        final decoder = const Utf8Decoder();
        await for (final lineRaw
            in resp.stream.transform(decoder).transform(const LineSplitter())) {
          if (controller.isClosed) break;
          final line = lineRaw.trim();
          if (line.isEmpty || !line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') {
            if (!controller.isClosed) controller.add(const LlmEvent.done());
            await controller.close();
            client.close();
            return;
          }
          try {
            final j = jsonDecode(payload) as Map<String, dynamic>;
            // HTTP 200 但返回错误帧
            if (j['error'] != null) {
              final err = j['error'];
              final msg = err is Map
                  ? (err['message']?.toString() ?? err.toString())
                  : err.toString();
              if (!controller.isClosed) {
                controller.addError('LLM error: $msg');
              }
              continue;
            }
            final delta = j['choices']?[0]?['delta']?['content'];
            if (delta is String && delta.isNotEmpty) {
              if (!controller.isClosed) controller.add(LlmEvent.delta(delta));
            }
            final usage = j['usage'];
            if (usage is Map) {
              if (!controller.isClosed) {
                controller.add(LlmEvent.usage(usage.cast()));
              }
            }
          } catch (_) {/* 忽略坏帧 */}
        }
        if (!controller.isClosed) controller.add(const LlmEvent.done());
        await controller.close();
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
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
  Future<String> chatOnce(
    List<ApiMessage> messages, {
    String? overrideModel,
    double? temperature,
    String? reasoningEffort,
  }) async {
    final m = overrideModel ?? config.model;
    final t = temperature ?? config.temperature;
    final body = <String, dynamic>{
      'model': m,
      'temperature': t,
      'max_tokens': config.maxTokens,
      'stream': false,
      'messages': messages.map((e) => e.toJson()).toList(),
    };
    if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
      body['reasoning_effort'] = reasoningEffort;
    }
    final resp = await http
        .post(
          _chatCompletionsUri(),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(body),
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
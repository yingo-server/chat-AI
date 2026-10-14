import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../utils/error_code.dart';

class ApiMessage {
  final String role;
  final String content;
  const ApiMessage(this.role, this.content);
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
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

/// 流式客户端 — 抛 AppError(带错误码)
class LlmStreamClient {
  final AiConfig config;
  LlmStreamClient(this.config);

  /// 错误码:Ec.llm00..llm09
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
        final req = http.Request('POST', Uri.parse(config.endpoint))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode(body);
        final resp = await client.send(req).timeout(
            Duration(seconds: config.requestTimeoutSeconds),
            onTimeout: () {
              throw AppError(Ec.llm05.code, Ec.llm05.message);
            });
        if (resp.statusCode != 200) {
          final err = await resp.stream.bytesToString();
          throw AppError(
            Ec.llm01.code,
            '${Ec.llm01.message}: ${err.length > 200 ? '${err.substring(0, 200)}…' : err}',
          );
        }
        String buffer = '';
        final decoder = const Utf8Decoder();
        await for (final chunk
            in resp.stream.transform(decoder).transform(const LineSplitter())) {
          if (controller.isClosed) break;
          buffer += chunk;
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
              final usage = j['usage'];
              if (usage is Map) {
                controller.add(LlmEvent.usage(usage.cast()));
              }
            } on FormatException catch (e) {
              throw AppError(Ec.llm04.code, Ec.llm04.message, cause: e);
            } catch (_) {/* 忽略坏帧 */}
          }
        }
        controller.add(const LlmEvent.done());
        await controller.close();
      } on AppError {
        if (!controller.isClosed) {
          controller.addError(LastLlmError());
          await controller.close();
        }
      } catch (e, st) {
        if (e is SocketException) {
          controller.addError(AppError(Ec.llm08.code, Ec.llm08.message, cause: e, stack: st));
        } else {
          controller.addError(AppError(Ec.llm00.code, Ec.llm00.message, cause: e, stack: st));
        }
        if (!controller.isClosed) await controller.close();
      } finally {
        client.close();
      }
    }

    run();
    controller.onCancel = () => client.close();
    return controller.stream;
  }

  /// 非流式;抛 AppError
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
    try {
      final resp = await http
          .post(
            Uri.parse(config.endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: config.requestTimeoutSeconds),
              onTimeout: () {
            throw AppError(Ec.llm05.code, Ec.llm05.message);
          });
      if (resp.statusCode != 200) {
        throw AppError(
          Ec.llm01.code,
          '${Ec.llm01.message}: ${resp.body}',
        );
      }
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final content = j['choices']?[0]?['message']?['content'] as String?;
      if (content == null) {
        throw AppError(Ec.llm06.code, Ec.llm06.message);
      }
      return content;
    } on AppError {
      rethrow;
    } on SocketException catch (e, st) {
      throw AppError(Ec.llm08.code, Ec.llm08.message, cause: e, stack: st);
    } catch (e, st) {
      throw AppError(Ec.llm07.code, Ec.llm07.message, cause: e, stack: st);
    }
  }
}

/// 占位错误类型,标识"流中抛了 AppError"
class LastLlmError implements Exception {
  @override
  String toString() => 'llm stream error';
}
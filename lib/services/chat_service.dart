import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../models/app_config.dart';
import '../models/chat.dart';
import '../utils/error_code.dart';
import '../widgets/stream/stream_buffer.dart';
import 'llm_client.dart';

/// 构造 OpenAI 兼容 messages(含系统提示词 + 周期提示词注入)
List<ApiMessage> buildPrompt({
  required Chat chat,
  required List<Message> visible,
  required AppConfig config,
  required bool injectHiddenThisTurn,
}) {
  final out = <ApiMessage>[];

  final primary = config.systemPrompts.isNotEmpty
      ? config.systemPrompts.first
      : SystemPrompt.defaultPrompt();
  var basePrompt = primary.content;
  if (chat.extraSystemPrompt != null && chat.extraSystemPrompt!.isNotEmpty) {
    basePrompt += '\n\n[对话级追加]\n${chat.extraSystemPrompt}';
  }
  out.add(ApiMessage('system', basePrompt));

  for (final m in visible.where((m) => m.role == MessageRole.compressed)) {
    out.add(ApiMessage('system', '[历史摘要]\n${m.content}'));
  }

  if (injectHiddenThisTurn) {
    out.add(ApiMessage('system', basePrompt));
  }

  for (final m in visible.where((m) =>
      m.role == MessageRole.user || m.role == MessageRole.assistant)) {
    out.add(ApiMessage(m.role == MessageRole.user ? 'user' : 'assistant',
        m.content));
  }
  return out;
}

/// ChatService — 所有失败抛 AppError(错误码)
class ChatService {
  ChatService(this._config, {LlmStreamClient? client})
      : _client = client ?? LlmStreamClient(_config.ai),
        _scheduler = PromptScheduler();

  AppConfig _config;
  AppConfig get config => _config;
  void updateConfig(AppConfig next) {
    _config = next;
    _client = LlmStreamClient(next.ai);
  }

  late LlmStreamClient _client;
  final PromptScheduler _scheduler;
  PromptScheduler get scheduler => _scheduler;

  /// 抛 AppError(Ec.ch00/Ec.ch08) 失败
  /// yield 完整 assistant 内容
  Stream<String> sendStream({
    required Chat chat,
    required List<Message> history,
    required String userText,
    required void Function(String chunk) onDelta,
    StreamBuffer? buffer,
    bool alreadyPersistedUserText = false,
  }) async* {
    if (!alreadyPersistedUserText) {
      try {
        final userMsg = Message(
          chatId: chat.id!,
          role: MessageRole.user,
          content: userText,
        );
        await AppDatabase.instance.insertMessage(userMsg);
      } catch (e, st) {
        if (e is AppError) rethrow;
        throw AppError(Ec.ch00.code, Ec.ch00.message, cause: e, stack: st);
      }
    } else if (chat.id == null) {
      throw AppError(Ec.md06.code, Ec.md06.message);
    }

    final userTurns = history
            .where((m) =>
                m.role == MessageRole.user || m.role == MessageRole.assistant)
            .length ~/
        2;
    final injectHidden = _scheduler.shouldInjectHidden(userTurns);
    final isFirstTurn = userTurns == 0;

    final List<ApiMessage> prompt;
    try {
      prompt = buildPrompt(
        chat: chat,
        visible: history,
        config: _config,
        injectHiddenThisTurn: injectHidden,
      );
      prompt.add(ApiMessage('user', userText));
    } catch (e, st) {
      throw AppError(Ec.ch01.code, Ec.ch01.message, cause: e, stack: st);
    }

    final full = StringBuffer();
    final stream = _client.chatStream(prompt, firstTurn: isFirstTurn);
    try {
      await for (final ev in stream) {
        if (ev.done) break;
        final d = ev.delta;
        if (d != null && d.isNotEmpty) {
          full.write(d);
          try {
            buffer?.add(d);
          } catch (e, st) {
            throw AppError(Ec.ch06.code, Ec.ch06.message, cause: e, stack: st);
          }
          onDelta(d);
        }
      }
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.ch06.code, Ec.ch06.message, cause: e, stack: st);
    }
    try {
      await buffer?.flush();
    } catch (e, st) {
      throw AppError(Ec.ch06.code, Ec.ch06.message, cause: e, stack: st);
    }

    try {
      await AppDatabase.instance.insertMessage(Message(
        chatId: chat.id!,
        role: MessageRole.assistant,
        content: full.toString(),
      ));
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError(Ec.ch02.code, Ec.ch02.message, cause: e);
    }
    try {
      await AppDatabase.instance.touchChat(chat.id!);
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError(Ec.ch03.code, Ec.ch03.message, cause: e);
    }

    unawaited(_safeCompress(chatId: chat.id!));

    yield full.toString();
  }

  /// 安全包装:不抛出给调用方
  Future<void> _safeCompress({required int chatId}) async {
    try {
      await maybeCompress(chatId: chatId);
    } on AppError catch (e) {
      // ignore: avoid_print
      debugPrint('compress failed: $e');
    } catch (e) {
      // ignore: avoid_print
      debugPrint('compress failed: $e');
    }
  }

  /// 抛 AppError;失败不影响主流程(由 _safeCompress 调用)
  Future<void> maybeCompress({required int chatId}) async {
    try {
      final ctx = _config.context;
      final all = await AppDatabase.instance
          .listMessages(chatId, includeCompressed: true);
      if (all.length < 2) return;
      final (live, _) = (() {
        final out = <Message>[];
        for (final m in all) {
          if (!m.compressed) out.add(m);
        }
        return (out, 0);
      })();
      if (live.length < ctx.compressTriggerMessages) return;

      final headCount = live.length - ctx.keepRecentMessages;
      if (headCount <= 0) return;

      final toCompress = live.take(headCount).toList();
      final priorSummary = (() {
        final parts = <String>[];
        for (final m in all) {
          if (m.role == MessageRole.compressed) parts.add(m.content);
        }
        return parts.join('\n');
      })();

      final transcript = StringBuffer();
      if (priorSummary.isNotEmpty) {
        transcript.writeln('[已有摘要]\n$priorSummary\n');
      }
      for (final m in toCompress) {
        transcript.writeln(
            '[${m.role == MessageRole.user ? '用户' : '助手'}] ${m.content}');
      }

      final prompt = [
        ApiMessage('system', ctx.compressPrompt),
        ApiMessage('user', transcript.toString()),
      ];

      String summary;
      try {
        final model = ctx.compressModel.isNotEmpty ? ctx.compressModel : null;
        summary = await _client.chatOnce(prompt,
            overrideModel: model,
            temperature: 0.2,
            reasoningEffort: 'none');
      } catch (e, st) {
        if (e is AppError) rethrow;
        throw AppError(Ec.ch04.code, Ec.ch04.message, cause: e, stack: st);
      }
      if (summary.trim().isEmpty) {
        throw AppError(Ec.ch05.code, Ec.ch05.message);
      }
      try {
        await AppDatabase.instance.insertMessage(Message(
          chatId: chatId,
          role: MessageRole.compressed,
          content: summary.trim(),
        ));
      } catch (e) {
        if (e is AppError) rethrow;
        throw AppError(Ec.ch04.code, Ec.ch04.message, cause: e);
      }
      try {
        await AppDatabase.instance.markMessagesCompressed(
            toCompress.map((m) => m.id!).toList());
      } catch (e) {
        if (e is AppError) rethrow;
        throw AppError(Ec.ch04.code, Ec.ch04.message, cause: e);
      }
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.ch04.code, Ec.ch04.message, cause: e, stack: st);
    }
  }
}

// debugPrint 兼容
class debugPrint {
  static void print(String s) {
    // ignore: avoid_print
    printx(s);
  }
}

void printx(String s) {
  // ignore: avoid_print
  print(s);
}
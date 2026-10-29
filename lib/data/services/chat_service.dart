import 'dart:async';

import '../../data/db/app_database.dart';
import '../../core/config/app_config.dart';
import '../../domain/chat.dart';
import '../../ui/widgets/stream/stream_buffer.dart';
import 'llm_client.dart';
import 'prompt_builder.dart';

/// 对话服务 — 流式发送 + 新对话预热 + 后台压缩
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

  /// 防止同一对话并发压缩
  final Set<int> _compressing = {};

  /// 最近一次实际发送的消息序列(诊断用)
  List<ApiMessage> _lastPrompt = const [];
  List<ApiMessage> get lastPrompt => _lastPrompt;

  Stream<String> sendStream({
    required Chat chat,
    required List<Message> history,
    required String userText,
    required void Function(String chunk) onDelta,
    StreamBuffer? buffer,
    bool alreadyPersistedUserText = false,
  }) async* {
    if (!alreadyPersistedUserText) {
      await AppDatabase.instance.insertMessage(Message(
        chatId: chat.id!,
        role: MessageRole.user,
        content: userText,
      ));
    }

    final priorMsgs = history
        .where((m) =>
            m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();
    final isFirstTurn = priorMsgs.isEmpty;

    // 新对话:静默预热(把提示词前缀送进服务端缓存;失败不影响对话)
    if (isFirstTurn) {
      try {
        await _client.chatOnce(
          const [
            ApiMessage('system', _warmupSystemMarker),
            ApiMessage('user', kWarmupPrompt),
          ],
          maxTokensOverride: 16,
          reasoningEffort: 'none',
        );
      } catch (_) {/* 忽略预热失败 */}
    }

    final prompt = buildPrompt(
        chat: chat, visible: history, config: _config);
    prompt.add(ApiMessage('user', userText));
    _lastPrompt = List<ApiMessage>.unmodifiable(prompt);

    final full = StringBuffer();
    final stream = _client.chatStream(prompt, firstTurn: isFirstTurn);
    try {
      await for (final ev in stream) {
        if (ev.done) break;
        final d = ev.delta;
        if (d != null && d.isNotEmpty) {
          full.write(d);
          buffer?.add(d);
          onDelta(d);
        }
      }

      await AppDatabase.instance.insertMessage(Message(
        chatId: chat.id!,
        role: MessageRole.assistant,
        content: full.toString(),
      ));
      await AppDatabase.instance.touchChat(chat.id!);
      unawaited(maybeCompress(chatId: chat.id!).catchError((_) {}));
      yield full.toString();
    } catch (e) {
      if (full.length > 0) {
        try {
          await AppDatabase.instance.insertMessage(Message(
            chatId: chat.id!,
            role: MessageRole.assistant,
            content: full.toString(),
          ));
        } catch (_) {}
      }
      rethrow;
    } finally {
      await buffer?.flush();
    }
  }

  /// 预热请求的 system(与正式提示词区分开,避免预热失败污染统计)
  static const String _warmupSystemMarker =
      'You are a session handshaker. Reply with the single word READY.';

  Future<void> maybeCompress({required int chatId}) async {
    if (_compressing.contains(chatId)) return;
    _compressing.add(chatId);
    try {
      await _maybeCompressLocked(chatId: chatId);
    } finally {
      _compressing.remove(chatId);
    }
  }

  Future<void> _maybeCompressLocked({required int chatId}) async {
    final ctx = _config.context;
    final all =
        await AppDatabase.instance.listMessages(chatId, includeCompressed: true);
    final live = all
        .where((m) => !m.compressed && m.role != MessageRole.compressed)
        .toList();
    if (live.length < ctx.compressTriggerMessages) return;

    final headCount = live.length - ctx.keepRecentMessages;
    if (headCount <= 0) return;

    final toCompress = live.take(headCount).toList();
    final priorSummary = all
        .where((m) => m.role == MessageRole.compressed)
        .map((m) => m.content)
        .join('\n');

    final transcript = StringBuffer();
    if (priorSummary.isNotEmpty) {
      transcript.writeln('[已有摘要]\n$priorSummary\n');
    }
    for (final m in toCompress) {
      transcript.writeln(
          '[${m.role == MessageRole.user ? '用户' : '助手'}] ${m.content}');
    }

    String summary;
    try {
      final model = ctx.compressModel.isNotEmpty ? ctx.compressModel : null;
      summary = await _client.chatOnce(
        [
          ApiMessage('system', ctx.compressPrompt),
          ApiMessage('user', transcript.toString()),
        ],
        overrideModel: model,
        temperature: 0.2,
        reasoningEffort: 'none',
      );
    } catch (_) {
      return;
    }
    if (summary.trim().isEmpty) return;

    await AppDatabase.instance.insertMessage(Message(
      chatId: chatId,
      role: MessageRole.compressed,
      content: summary.trim(),
    ));
    await AppDatabase.instance
        .markMessagesCompressed(toCompress.map((m) => m.id!).toList());
  }
}

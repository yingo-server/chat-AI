import 'dart:async';

import '../db/app_database.dart';
import '../models/app_config.dart';
import '../models/chat.dart';
import '../widgets/stream/stream_buffer.dart';
import 'llm_client.dart';

/// 把"该对话可见的真实消息"加上系统/隐藏提示词,组装成发给 LLM 的 ApiMessage 列表
List<ApiMessage> buildPrompt({
  required Chat chat,
  required List<Message> visible,
  required AppConfig config,
  required bool injectHiddenThisTurn,
}) {
  final out = <ApiMessage>[];

  // 1. 主系统提示词(始终注入,作为基线)
  final primary = config.systemPrompts.isNotEmpty
      ? config.systemPrompts.first
      : SystemPrompt.defaultPrompt();
  var basePrompt = primary.content;
  if (chat.extraSystemPrompt != null && chat.extraSystemPrompt!.isNotEmpty) {
    basePrompt += '\n\n[对话级追加]\n${chat.extraSystemPrompt}';
  }
  out.add(ApiMessage('system', basePrompt));

  // 2. 早期压缩摘要
  for (final m in visible.where((m) => m.role == MessageRole.compressed)) {
    out.add(ApiMessage('system', '[历史摘要]\n${m.content}'));
  }

  // 3. 隐藏再注入:2~4 轮一次,把基线提示词再发一次(用户看不见这段)
  if (injectHiddenThisTurn) {
    out.add(ApiMessage('system', basePrompt));
  }

  // 4. 真实对话消息
  for (final m in visible.where((m) =>
      m.role == MessageRole.user || m.role == MessageRole.assistant)) {
    out.add(ApiMessage(m.role == MessageRole.user ? 'user' : 'assistant',
        m.content));
  }
  return out;
}

/// 对话服务 — 流式发送 + 后台压缩 + 隐藏 system 提示词轮询
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

  /// 每个聊天同一时刻只允许一次压缩,防止并发重入
  final Set<int> _compressing = {};

  Stream<String> sendStream({
    required Chat chat,
    required List<Message> history,
    required String userText,
    required void Function(String chunk) onDelta,
    StreamBuffer? buffer,
    bool alreadyPersistedUserText = false,
  }) async* {
    if (!alreadyPersistedUserText) {
      final userMsg = Message(
        chatId: chat.id!,
        role: MessageRole.user,
        content: userText,
      );
      await AppDatabase.instance.insertMessage(userMsg);
    }

    // 调用方契约:history 不包含本轮 userText,由下方 prompt.add 单独追加
    final userTurns = history
            .where((m) =>
                m.role == MessageRole.user || m.role == MessageRole.assistant)
            .length ~/
        2;
    final injectHidden = _scheduler.shouldInjectHidden(userTurns);
    // 首轮:userTurns == 0(对话没历史 user-assistant 对)=> 用 firstTurnReasoning
    // 之后:用 subsequentReasoning(默认 'none' = 关闭思考)
    final isFirstTurn = userTurns == 0;

    final prompt = buildPrompt(
      chat: chat,
      visible: history,
      config: _config,
      injectHiddenThisTurn: injectHidden,
    );
    prompt.add(ApiMessage('user', userText));

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

      final assistant = Message(
        chatId: chat.id!,
        role: MessageRole.assistant,
        content: full.toString(),
      );
      await AppDatabase.instance.insertMessage(assistant);
      await AppDatabase.instance.touchChat(chat.id!);

      unawaited(
          maybeCompress(chatId: chat.id!).catchError((_) {}));

      yield full.toString();
    } catch (e) {
      // 出错也要把已收到的部分落库,避免丢字
      if (full.length > 0) {
        try {
          await AppDatabase.instance.insertMessage(Message(
            chatId: chat.id!,
            role: MessageRole.assistant,
            content: full.toString(),
          ));
        } catch (_) {/* 落库失败则忽略 */}
      }
      rethrow;
    } finally {
      // flush 不应抛出(即使已 dispose)
      await buffer?.flush();
    }
  }

  /// 后台压缩
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
    } catch (_) {
      return;
    }
    if (summary.trim().isEmpty) return;

    final summaryMsg = Message(
      chatId: chatId,
      role: MessageRole.compressed,
      content: summary.trim(),
    );
    await AppDatabase.instance.insertMessage(summaryMsg);
    await AppDatabase.instance.markMessagesCompressed(
        toCompress.map((m) => m.id!).toList());
  }
}
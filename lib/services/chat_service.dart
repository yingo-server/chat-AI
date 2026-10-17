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
  final basePrompt = _primaryPrompt(chat, config);
  out.add(ApiMessage('system', basePrompt));

  // 2. 早期压缩摘要
  for (final m in visible.where((m) => m.role == MessageRole.compressed)) {
    out.add(ApiMessage('system', '[历史摘要]\n${m.content}'));
  }

  // 3. 隐藏再注入:每轮一次,把基线提示词再发一次(用户看不见这段)
  if (injectHiddenThisTurn) {
    out.add(ApiMessage('system', basePrompt));
  }

  // 4. 预热段:新建对话时静默发出的一次"初始化握手",
  //    [user(初始化指令) / assistant(READY)] 让提示词进入服务端前缀缓存,
  //    同时把提示词固化为对话历史的一部分(对齐三种实测方案中的最优)
  out.add(const ApiMessage('user', _warmupPrompt));
  out.add(const ApiMessage('assistant', _warmupReply));

  // 5. 真实对话消息;本轮 user 之前再注入一次 system(三明治结构,
  //    实测对长上下文的遵循度最好)
  final historyMsgs = visible.where((m) =>
      m.role == MessageRole.user || m.role == MessageRole.assistant).toList();
  for (var i = 0; i < historyMsgs.length; i++) {
    final m = historyMsgs[i];
    if (i == historyMsgs.length - 1 && injectHiddenThisTurn) {
      out.add(ApiMessage('system', basePrompt));
    }
    out.add(ApiMessage(m.role == MessageRole.user ? 'user' : 'assistant',
        m.content));
  }
  return out;
}

/// 对话的基线系统提示词(模板 + 对话级追加)
String _primaryPrompt(Chat chat, AppConfig config) {
  final primary = config.systemPrompts.isNotEmpty
      ? config.systemPrompts.first
      : SystemPrompt.defaultPrompt();
  var base = primary.content;
  if (chat.extraSystemPrompt != null && chat.extraSystemPrompt!.isNotEmpty) {
    base += '\n\n[对话级追加]\n${chat.extraSystemPrompt}';
  }
  return base;
}

/// 预热轮的固定初始化指令(不面向用户)
const String _warmupPrompt =
    '(session init — acknowledge with the single word: READY)';

/// 预热轮的固定应答
const String _warmupReply = 'READY';

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

  /// 最近一次实际发送的完整消息序列(含 system 提示词),供界面核对
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
      final userMsg = Message(
        chatId: chat.id!,
        role: MessageRole.user,
        content: userText,
      );
      await AppDatabase.instance.insertMessage(userMsg);
    }

    // 调用方契约:history 只含【本对话】的历史,且不含本轮 userText。
    // 因此下面的轮次统计天然是"对话级"的 —— 新对话首条消息必然为 0 轮,
    // 与其它对话互不影响(ChatService / PromptScheduler 均为每对话一份实例)。
    final priorMsgs = history
        .where((m) =>
            m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();
    final userTurns = priorMsgs.length ~/ 2;
    // 按要求:每轮都重复注入一次系统提示词,确保始终生效
    // (早期实现为每 2~4 轮一次,实测长对话中偶有"提示词失效"的观感)
    const injectHidden = true;
    // 首轮:本对话尚无任何 user/assistant 消息(不依赖配对数,避免悬空消息误判)
    final isFirstTurn = priorMsgs.isEmpty;

    // 新建对话(无任何历史)时,先静默发一次预热请求:
    // 服务端把提示词前缀写入缓存,后续每轮都命中;预热应答也存入数据库,
    // 成为对话历史的一部分,提示词因此"固化"在上下文里。
    if (history.isEmpty) {
      try {
        await _client.chatOnce(
          [
            ApiMessage('system', _primaryPrompt(chat, _config)),
            ApiMessage('system', _primaryPrompt(chat, _config)),
            const ApiMessage('user', _warmupPrompt),
          ],
          maxTokensOverride: 16,
          reasoningEffort: 'none',
        );
      } catch (_) {
        // 预热失败不阻塞对话,仅失去缓存收益
      }
    }

    final prompt = buildPrompt(
      chat: chat,
      visible: history,
      config: _config,
      injectHiddenThisTurn: injectHidden,
    );
    prompt.add(ApiMessage('user', userText));

    // 记录实际发送内容(界面"系统提示词"面板直接读取这里)
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
import 'dart:async';

import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../utils/dialogs.dart';
import '../widgets/animation/message_animations.dart';
import '../widgets/chat/message_bubble.dart' as chat;
import '../widgets/chat/streaming_bubble.dart';
import '../widgets/export_sheet.dart';
import '../widgets/prompt/recurring_status.dart';
import '../widgets/stream/stream_buffer.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();

  AppConfig? _config;
  ChatService? _service;

  List<Message> _messages = [];
  bool _busy = false;

  /// 实时流式缓冲器 — 接收上游 token,定时释放
  StreamBuffer? _buffer;

  /// 当前正在跑的流,可被取消
  StreamSubscription<String>? _runSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _runSub?.cancel();
    _buffer?.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final scope = ConfigScope.of(context);
    final cfg = await scope.store.load();
    final svc = ChatService(cfg);
    final msgs = await AppDatabase.instance
        .listMessages(widget.chat.id!, includeCompressed: false);
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _service = svc;
      _messages = msgs;
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (_service == null || _config == null) return;

    // 先落库用户消息(乐观 UI)
    final persisted = await AppDatabase.instance.insertMessage(Message(
      chatId: widget.chat.id!,
      role: MessageRole.user,
      content: text,
    ));

    final baseHistory = await AppDatabase.instance
        .listMessages(widget.chat.id!, includeCompressed: false);

    // 准备缓冲器
    final buf = StreamBuffer(
      charsPerSecond: _config!.ai.streamCharsPerSecond,
    );
    setState(() {
      _messages = baseHistory;
      _busy = true;
      _buffer = buf;
      _input.clear();
    });
    _scrollToEnd();

    String? err;
    try {
      final stream = _service!.sendStream(
        chat: widget.chat,
        history: _messages.where((m) => m.id != persisted).toList(),
        userText: text,
        alreadyPersistedUserText: true,
        buffer: buf,
        onDelta: (_) {/* 由 buffer 控制节奏 */},
      );
      await for (final _ in stream) {
        // drain
      }
    } catch (e) {
      err = e.toString();
    }

    final msgs = await AppDatabase.instance
        .listMessages(widget.chat.id!, includeCompressed: false);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _busy = false;
      _buffer?.dispose();
      _buffer = null;
    });
    _scrollToEnd();
    if (err != null) showSnack(context, '错误: $err', error: true);
  }

  Future<void> _stop() async {
    await _runSub?.cancel();
    _runSub = null;
    await _buffer?.flush();
    final msgs = await AppDatabase.instance
        .listMessages(widget.chat.id!, includeCompressed: false);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _busy = false;
      _buffer?.dispose();
      _buffer = null;
    });
    showSnack(context, '已停止');
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut);
    });
  }

  Future<void> _export() async {
    await showExportSheet(context, chat: widget.chat, messages: _messages);
  }

  Future<void> _editSystemPrompt() async {
    final cur = widget.chat.extraSystemPrompt ?? '';
    final ctrl = TextEditingController(text: cur);
    final next = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('本对话追加系统提示词'),
        content: TextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: '仅作用于本对话,可留空')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (next == null) return;
    final updated = widget.chat.copyWith(
        extraSystemPrompt: next.isEmpty ? null : next,
        updatedAt: DateTime.now());
    await AppDatabase.instance.updateChat(updated);
    if (!mounted) return;
    showSnack(context, next.isEmpty ? '已清除' : '已更新本对话的附加提示词');
  }

  void _showPromptStatus() {
    final svc = _service;
    if (svc == null) return;
    final userTurns = _messages
            .where((m) =>
                m.role == MessageRole.user ||
                m.role == MessageRole.assistant)
            .length ~/
        2;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: RecurringPromptsStatusCard(
          prompts: _config?.recurringPrompts ?? const [],
          cursor: svc.scheduler.cursor,
          turnsCompleted: userTurns,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasConfig = _config != null && _config!.ai.isValid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '周期提示词状态',
            icon: const Icon(Icons.rule),
            onPressed: _showPromptStatus,
          ),
          IconButton(
            tooltip: '本对话提示词',
            icon: const Icon(Icons.tune),
            onPressed: _editSystemPrompt,
          ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasConfig)
            MaterialBanner(
              backgroundColor: scheme.errorContainer,
              leading: Icon(Icons.warning_amber_rounded,
                  color: scheme.onErrorContainer),
              content: Text('请先在设置中填写 API 信息',
                  style: TextStyle(color: scheme.onErrorContainer)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen())),
                  child: const Text('去设置'),
                ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: ListView.builder(
                key: ValueKey(_messages.length),
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                itemCount: _messages.length + (_busy ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i < _messages.length) {
                    final m = _messages[i];
                    return FadeInUp(
                      key: ValueKey('m-${m.id ?? m.createdAt}'),
                      child: chat.MessageBubble(message: m),
                    );
                  }
                  // 流式占位
                  return StreamBuilder<String>(
                    key: const ValueKey('streaming'),
                    stream: _buffer?.displayed ??
                        const Stream<String>.empty(),
                    initialData: '',
                    builder: (_, snap) {
                      return StreamingBubble(
                        text: snap.data ?? '',
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        hintText: '输入消息…',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: _busy
                        ? FilledButton.tonalIcon(
                            key: const ValueKey('stop'),
                            onPressed: _stop,
                            icon: const Icon(Icons.stop),
                            label: const Text('停止'),
                          )
                        : IconButton.filled(
                            key: const ValueKey('send'),
                            onPressed: hasConfig ? _send : null,
                            icon: const Icon(Icons.arrow_upward),
                            tooltip: '发送',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


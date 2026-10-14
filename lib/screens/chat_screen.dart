import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/app_database.dart';
import '../main.dart' show ConfigScope;
import '../models/app_config.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../widgets/chat/message_bubble.dart' as chat;
import '../widgets/chat/streaming_bubble.dart';
import '../widgets/export_sheet.dart';
import '../widgets/stream/stream_buffer.dart';

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
  bool _stopRequested = false;
  StreamBuffer? _buffer;

  /// 已附加的图片 / 文件,会在本轮发送时一起发出
  final List<_Attachment> _attachments = [];

  /// 占位 ValueNotifier — 当没有活跃缓冲时使用
  static final _emptyTextNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    // 推迟到首帧后,避免 initState 中访问 InheritedWidget(ConfigScope.of)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
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

  // ===== 附件 =====

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      setState(() => _attachments.add(
          _Attachment.image(File(picked.path), picked.name)));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '图片选择失败: $e', error: true);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.path == null) return;
      if (!mounted) return;
      setState(() => _attachments.add(
          _Attachment.file(File(f.path!), f.name)));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '文件选择失败: $e', error: true);
    }
  }

  void _removeAttachment(_Attachment a) {
    setState(() => _attachments.remove(a));
  }

  // ===== 发送 =====

  Future<void> _send() async {
    if (_busy) return;
    var text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_service == null || _config == null) return;

    // 立即(同步,任何 await 之前)置忙,防止重入
    _busy = true;
    _stopRequested = false;

    // 把附件信息拼到 user 消息里(OpenAI images:[text]/... 格式)
    if (_attachments.isNotEmpty) {
      final parts = StringBuffer();
      parts.writeln(text);
      for (final a in _attachments) {
        if (a.isImage) {
          parts.writeln('\n[图片附件: ${a.name}]');
        } else {
          parts.writeln('\n[文件附件: ${a.name}]');
        }
      }
      text = parts.toString().trim();
    }

    final buf = StreamBuffer(
      charsPerSecond: _resolveStreamSpeed(_config!.userPrefs),
      maxBuffer: _resolveBufferSize(_config!.userPrefs),
    );
    setState(() {
      _busy = true;
      _buffer = buf;
      _input.clear();
      _attachments.clear();
    });

    try {
      final persisted = await AppDatabase.instance.insertMessage(Message(
        chatId: widget.chat.id!,
        role: MessageRole.user,
        content: text,
      ));

      final baseHistory = await AppDatabase.instance
          .listMessages(widget.chat.id!, includeCompressed: false);

      if (!mounted) return;
      setState(() => _messages = baseHistory);
      _scrollToEnd();

      await for (final _ in _service!.sendStream(
        chat: widget.chat,
        history: _messages.where((m) => m.id != persisted).toList(),
        userText: text,
        alreadyPersistedUserText: true,
        buffer: buf,
        onDelta: (_) {
          // 用户点了停止 → 后续 chunk 直接丢弃(不取消底层流)
          if (_stopRequested) return;
        },
      )) {
        // drain
      }
    } catch (e) {
      if (mounted) showSnack(context, '错误: $e', error: true);
    } finally {
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
    }
  }

  /// 按 userPrefs 互斥规则计算 StreamBuffer 参数
  /// bufferSize>0 → 纯缓冲模式(speed=0);否则 streamSpeed>0 → 限速模式(maxBuffer=0)
  double _resolveStreamSpeed(UserPrefs p) =>
      p.bufferSize > 0 ? 0.0 : p.streamSpeed.toDouble();
  int _resolveBufferSize(UserPrefs p) =>
      p.streamSpeed > 0 ? 0 : p.bufferSize;
  // 互斥语义:两者都>0 时以 speed 为准(bufferSize 让位) — 上面的三元顺序即体现了该优先级

  Future<void> _stop() async {
    // 仅翻转 UI 标志并置停止请求位;流本身由 _send 的 finally 收尾
    _stopRequested = true;
    if (!mounted) return;
    setState(() => _busy = false);
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
    await showExportSheet(context,
        chat: widget.chat, messages: _messages);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasConfig = _config != null && _config!.ai.isValid;
    final prefs = _config?.userPrefs ?? UserPrefs.defaults;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chat.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '导出 Markdown',
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
              content: Text('请检查配置',
                  style: TextStyle(color: scheme.onErrorContainer)),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey(_messages.length),
              controller: _scroll,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              itemCount: _messages.length + (_busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (i < _messages.length) {
                  return chat.MessageBubble(message: _messages[i]);
                }
                return ValueListenableBuilder<String>(
                  key: const ValueKey('streaming'),
                  valueListenable:
                      _buffer?.displayed ?? _emptyTextNotifier,
                  builder: (_, text, __) => StreamingBubble(text: text),
                );
              },
            ),
          ),
          if (_attachments.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in _attachments)
                    InputChip(
                      avatar: Icon(
                          a.isImage ? Icons.image : Icons.insert_drive_file,
                          size: 16),
                      label: Text(a.name, overflow: TextOverflow.ellipsis),
                      onDeleted: () => _removeAttachment(a),
                    ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '附加图片',
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _busy ? null : _pickImage,
                  ),
                  IconButton(
                    tooltip: '附加文件',
                    icon: const Icon(Icons.attach_file),
                    onPressed: _busy ? null : _pickFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_busy,
                      style: TextStyle(fontSize: prefs.fontSize.toDouble()),
                      decoration: InputDecoration(
                        hintText: '输入消息…',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
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

class _Attachment {
  final File file;
  final String name;
  final bool isImage;
  _Attachment.image(this.file, this.name) : isImage = true;
  _Attachment.file(this.file, this.name) : isImage = false;
}
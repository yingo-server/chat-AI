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
import '../theme/motion.dart';
import '../theme/spacing.dart';
import '../utils/dialogs.dart';
import '../utils/vault.dart';
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

  /// 是否已停在列表底部(用于显示"回到最新"按钮)
  bool _atBottom = true;

  /// 自动下拉阈值:距底部小于该像素值即视为在底部(参考 Telegram/微信的 120px 量级)
  static const double _autoScrollThreshold = 120;
  StreamBuffer? _buffer;

  /// 已附加的图片 / 文件,会在本轮发送时一起发出
  final List<_Attachment> _attachments = [];

  /// 占位 ValueNotifier — 当没有活跃缓冲时使用
  static final _emptyTextNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // 推迟到首帧后,避免 initState 中访问 InheritedWidget(ConfigScope.of)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // 阈值:距底部 120px 以内视为"在底部"(参考主流聊天应用的经验阈值)
    final at = _scroll.position.pixels >=
        _scroll.position.maxScrollExtent - _autoScrollThreshold;
    if (at != _atBottom) setState(() => _atBottom = at);
  }

  /// 是否应跟随新内容:用户停在底部时才自动下拉
  bool get _shouldAutoScroll => _atBottom;

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
    await scope.ready; // 等待首帧后的保险库/配置初始化
    final cfg = scope.controller.config;
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

    // 输出速度(用户可调)+ 固定 100 字缓冲上限(内部抗抖动)
    final buf = StreamBuffer(
      charsPerSecond: _config!.userPrefs.streamSpeed.toDouble(),
      maxBuffer: StreamBuffer.fixedMaxBuffer,
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
      if (_shouldAutoScroll) _scrollToEnd();

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

  Future<void> _stop() async {
    // 仅翻转 UI 标志并置停止请求位;流本身由 _send 的 finally 收尾
    _stopRequested = true;
    if (!mounted) return;
    setState(() => _busy = false);
    showSnack(context, '已停止');
  }

  void _scrollToEnd() {
    if (!_shouldAutoScroll) return; // 用户已上滚 → 不打扰
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: Motion.medium2, curve: Motion.emphasizedDecelerate);
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
            tooltip: '导出文本',
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasConfig)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
              child: Card(
                color: scheme.errorContainer,
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.error_outline,
                      color: scheme.onErrorContainer),
                  title: Text('配置加载失败',
                      style: TextStyle(color: scheme.onErrorContainer)),
                  subtitle: Text('错误码 ${Vault.lastError}',
                      style: TextStyle(
                          color: scheme.onErrorContainer.withOpacity(0.8))),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                  Gap.lg, Gap.md, Gap.lg, Gap.sm),
              itemCount: _messages.length + (_busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (i < _messages.length) {
                  final bubble = chat.MessageBubble(message: _messages[i]);
                  final isNewest = i == _messages.length - 1 && !_busy;
                  return isNewest ? MotionEntrance(child: bubble) : bubble;
                }
                return ValueListenableBuilder<String>(
                  key: const ValueKey('streaming'),
                  valueListenable:
                      _buffer?.displayed ?? _emptyTextNotifier,
                  builder: (_, text, __) => StreamingBubble(text: text),
                );
              },
            ),
                // M3:FAB 用于"回到最新",仅在离开底部时出现
                Positioned(
                  right: Gap.lg,
                  bottom: Gap.lg,
                  child: AnimatedScale(
                    scale: _atBottom ? 0 : 1,
                    duration: Motion.short4,
                    curve: Motion.emphasizedDecelerate,
                    child: FloatingActionButton.small(
                      heroTag: 'jumpToLatest',
                      tooltip: '回到最新',
                      onPressed: _scrollToEnd,
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_attachments.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
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
              padding: Insets.composer,
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
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontSize: prefs.fontSize.toDouble()),
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: '输入消息…',
                        isDense: true,
                        fillColor: scheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        border: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(28)),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(28)),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(28)),
                          borderSide:
                              BorderSide(color: scheme.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  AnimatedSwitcher(
                    duration: Motion.short4,
                    switchInCurve: Motion.emphasizedDecelerate,
                    switchOutCurve: Motion.emphasizedAccelerate,
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
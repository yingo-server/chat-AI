import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/db/app_database.dart';
import '../../main.dart' show ConfigScope;
import '../../core/config/app_config.dart';
import '../../domain/chat.dart';
import '../../data/services/chat_stream_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/dialogs.dart';
import '../../core/vault/vault.dart';
import '../widgets/chat/message_bubble.dart' as chat;
import '../widgets/chat/streaming_bubble.dart';
import '../widgets/chat/typing_dots.dart';
import '../widgets/export_sheet.dart';


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

  List<Message> _messages = [];

  /// 流式状态由应用级管理器持有 —— 离开页面也能继续输出并落库
  ChatStreamManager get _manager => ChatStreamManager.instance;
  int get _chatId => widget.chat.id!;
  bool get _busy => _manager.isBusy(_chatId);
  bool _wasBusy = false;

  /// 是否已停在列表底部(用于显示"回到最新"按钮)
  bool _atBottom = true;

  /// 自动下拉阈值:距底部小于该像素值即视为在底部(参考 Telegram/微信的 120px 量级)
  static const double _autoScrollThreshold = 120;

  /// 已附加的图片 / 文件,会在本轮发送时一起发出
  final List<_Attachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _manager.addListener(_onManagerChanged);
    _wasBusy = _busy;
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
    _manager.removeListener(_onManagerChanged);
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final scope = ConfigScope.of(context);
    await scope.ready; // 等待首帧后的保险库/配置初始化
    final cfg = scope.controller.config;
    final msgs = await AppDatabase.instance
        .listMessages(_chatId, includeCompressed: false);
    if (!mounted) return;
    setState(() {
      _config = cfg;
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

  /// 附件选择:统一入口,底部表单二选一(图片 / 文件)
  Future<void> _showAttachSheet() async {
    final s = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image_outlined, color: s.onSurfaceVariant),
              title: const Text('图片'),
              subtitle: const Text('从相册选择'),
              onTap: () => Navigator.pop(sheetCtx, 'image'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file, color: s.onSurfaceVariant),
              title: const Text('文件'),
              subtitle: const Text('选择任意文件'),
              onTap: () => Navigator.pop(sheetCtx, 'file'),
            ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'image') await _pickImage();
    if (choice == 'file') await _pickFile();
  }

  // ===== 发送 =====

  Future<void> _send() async {
    if (_busy) return;
    var text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_config == null) return;

    // 附件信息拼进正文
    if (_attachments.isNotEmpty) {
      final parts = StringBuffer();
      parts.writeln(text);
      for (final a in _attachments) {
        parts.writeln(a.isImage ? '\n[图片附件: ${a.name}]' : '\n[文件附件: ${a.name}]');
      }
      text = parts.toString().trim();
    }

    setState(() {
      _input.clear();
      _attachments.clear();
    });

    try {
      // 先落库用户消息(乐观显示)
      await AppDatabase.instance.insertMessage(Message(
        chatId: _chatId,
        role: MessageRole.user,
        content: text,
      ));
      final msgs =
          await AppDatabase.instance.listMessages(_chatId, includeCompressed: false);
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (_shouldAutoScroll) _scrollToEnd();

      // 交给应用级管理器:离开页面也会继续
      unawaited(_manager.start(
        chat: widget.chat,
        config: _config!,
        userText: text,
        alreadyPersistedUserText: true,
      ));
    } catch (e) {
      if (mounted) showSnack(context, '错误: $e', error: true);
    }
  }

  /// 管理器状态变化:开始/结束都刷新界面;结束时重读消息
  void _onManagerChanged() {
    if (!mounted) return;
    final busy = _busy;
    if (_wasBusy && !busy) {
      // 会话结束 → 重新加载消息(助手回复已落库)
      AppDatabase.instance
          .listMessages(_chatId, includeCompressed: false)
          .then((msgs) {
        if (!mounted) return;
        setState(() => _messages = msgs);
        _scrollToEnd();
      });
    }
    _wasBusy = busy;
    setState(() {});
  }

  Future<void> _stop() async {
    _manager.cancel(_chatId);
    if (!mounted) return;
    setState(() {});
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
                // 流式占位:收到首 token 前显示"三点"动画,之后逐步淡入
                final partial = _manager.partialOf(_chatId);
                if (partial == null) return const SizedBox.shrink();
                return ValueListenableBuilder<String>(
                  key: const ValueKey('streaming'),
                  valueListenable: partial,
                  builder: (_, text, __) => text.isEmpty
                      ? const ThinkingBubble()
                      : StreamingBubble(text: text),
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
          // ── 底部输入区 ─────────────────────────────────────────
          // M3 组合输入条:单个圆角容器承载 [附件][输入框][发送],
          // 容器本身有描边与轻微投影,文本域无边框,避免"框套框"。
          SafeArea(
            top: false,
            child: Padding(
              padding: Insets.composer,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withAlpha(_busy ? 0 : 14),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 附件入口:单个按钮,弹出选择
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: IconButton(
                        tooltip: '添加附件',
                        icon: const Icon(Icons.add_rounded),
                        color: scheme.onSurfaceVariant,
                        onPressed: _busy ? null : _showAttachSheet,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 6,
                        enabled: !_busy,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                              fontSize: prefs.fontSize.toDouble(),
                              height: 1.4,
                            ),
                        decoration: const InputDecoration(
                          hintText: '输入消息…',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    // 发送 / 停止
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 4, right: 6, bottom: 6),
                      child: AnimatedSwitcher(
                        duration: Motion.short4,
                        switchInCurve: Motion.emphasizedDecelerate,
                        switchOutCurve: Motion.emphasizedAccelerate,
                        child: SizedBox(
                          key: ValueKey(_busy ? 'stop' : 'send'),
                          width: 40,
                          height: 40,
                          child: _busy
                              ? IconButton.filledTonal(
                                  tooltip: '停止',
                                  onPressed: _stop,
                                  icon: const Icon(Icons.stop_rounded,
                                      size: 20),
                                )
                              : IconButton.filled(
                                  tooltip: '发送',
                                  onPressed: hasConfig ? _send : null,
                                  icon: const Icon(Icons.arrow_upward_rounded,
                                      size: 20),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
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
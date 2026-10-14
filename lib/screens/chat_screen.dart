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
import '../utils/error_code.dart';
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
  StreamBuffer? _buffer;
  final List<_Attachment> _attachments = [];

  static final _emptyTextNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
    try {
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
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc15.code, Ec.sc15.message, cause: e, stack: st);
    }
  }

  // ===== 附件 =====

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() => _attachments.add(
          _Attachment.image(File(picked.path), picked.name)));
    } on AppError {
      rethrow;
    } catch (e, st) {
      if (!mounted) return;
      showSnack(context, '图片选择失败: ${ecMessage(e)}', error: true);
      throw AppError(Ec.sc10.code, Ec.sc10.message, cause: e, stack: st);
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
      if (f.path == null) {
        throw AppError(Ec.pf02.code, Ec.pf02.message);
      }
      setState(() =>
          _attachments.add(_Attachment.file(File(f.path!), f.name)));
    } on AppError {
      rethrow;
    } catch (e, st) {
      if (!mounted) return;
      showSnack(context, '文件选择失败: ${ecMessage(e)}', error: true);
      throw AppError(Ec.sc11.code, Ec.sc11.message, cause: e, stack: st);
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
    if (_service == null || _config == null) {
      showSnack(context, '尚未就绪', error: true);
      return;
    }
    if (widget.chat.id == null) {
      throw AppError(Ec.md06.code, Ec.md06.message);
    }

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

    late int persisted;
    try {
      persisted = await AppDatabase.instance.insertMessage(Message(
        chatId: widget.chat.id!,
        role: MessageRole.user,
        content: text,
      ));
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.ch08.code, Ec.ch08.message, cause: e, stack: st);
    }

    late List<Message> baseHistory;
    try {
      baseHistory = await AppDatabase.instance
          .listMessages(widget.chat.id!, includeCompressed: false);
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.ch07.code, Ec.ch07.message, cause: e, stack: st);
    }

    final buf = StreamBuffer(
      charsPerSecond: _resolveStreamSpeed(_config!.userPrefs),
      maxBuffer: _resolveBufferSize(_config!.userPrefs),
    );
    setState(() {
      _messages = baseHistory;
      _busy = true;
      _buffer = buf;
      _input.clear();
      _attachments.clear();
    });
    try {
      _scrollToEnd();
    } catch (e, st) {
      throw AppError(Ec.sc16.code, Ec.sc16.message, cause: e, stack: st);
    }

    String? err;
    try {
      await for (final _ in _service!.sendStream(
        chat: widget.chat,
        history: _messages.where((m) => m.id != persisted).toList(),
        userText: text,
        alreadyPersistedUserText: true,
        buffer: buf,
        onDelta: (_) {},
      )) {
        // drain
      }
    } on AppError catch (e) {
      err = e.toString();
    } catch (e, st) {
      err = AppError(Ec.sc13.code, Ec.sc13.message, cause: e, stack: st).toString();
    }

    late List<Message> msgs;
    try {
      msgs = await AppDatabase.instance
          .listMessages(widget.chat.id!, includeCompressed: false);
    } on AppError catch (e) {
      err = e.toString();
      msgs = _messages;
    } catch (e, st) {
      err = AppError(Ec.ch07.code, Ec.ch07.message, cause: e, stack: st).toString();
      msgs = _messages;
    }

    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _busy = false;
      _buffer?.dispose();
      _buffer = null;
    });
    try {
      _scrollToEnd();
    } catch (e, st) {
      throw AppError(Ec.sc16.code, Ec.sc16.message, cause: e, stack: st);
    }
    if (err != null) showSnack(context, err, error: true);
  }

  double _resolveStreamSpeed(UserPrefs p) =>
      p.bufferSize > 0 ? 0.0 : p.streamSpeed.toDouble();
  int _resolveBufferSize(UserPrefs p) =>
      p.streamSpeed > 0 ? 0 : p.bufferSize;

  Future<void> _stop() async {
    try {
      setState(() {
        _busy = false;
        _buffer?.dispose();
        _buffer = null;
      });
      showSnack(context, '已停止');
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc14.code, Ec.sc14.message, cause: e, stack: st);
    }
  }

  void _scrollToEnd() {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      });
    } catch (e, st) {
      throw AppError(Ec.sc16.code, Ec.sc16.message, cause: e, stack: st);
    }
  }

  Future<void> _export() async {
    try {
      await showExportSheet(context,
          chat: widget.chat, messages: _messages);
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc06.code, Ec.sc06.message, cause: e, stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
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
                    try {
                      return chat.MessageBubble(message: _messages[i]);
                    } catch (e, st) {
                      throw AppError(Ec.wd00.code, Ec.wd00.message,
                          cause: e, stack: st);
                    }
                  }
                  return ValueListenableBuilder<String>(
                    key: const ValueKey('streaming'),
                    valueListenable:
                        _buffer?.displayed ?? _emptyTextNotifier,
                    builder: (_, text, __) {
                      try {
                        return StreamingBubble(text: text);
                      } catch (e, st) {
                        throw AppError(Ec.wd01.code, Ec.wd01.message,
                            cause: e, stack: st);
                      }
                    },
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
                            a.isImage
                                ? Icons.image
                                : Icons.insert_drive_file,
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
                        style:
                            TextStyle(fontSize: prefs.fontSize.toDouble()),
                        decoration: const InputDecoration(
                          hintText: '输入消息…',
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          try {
                            _send();
                          } on AppError catch (e) {
                            showSnack(context, ecMessage(e), error: true);
                          } catch (e, st) {
                            showSnack(
                                context,
                                AppError(Ec.sc17.code, Ec.sc17.message,
                                        cause: e, stack: st)
                                    .toString(),
                                error: true);
                          }
                        },
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
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc00.code, Ec.sc00.message, cause: e, stack: st);
    }
  }
}

class _Attachment {
  final File file;
  final String name;
  final bool isImage;
  _Attachment.image(this.file, this.name) : isImage = true;
  _Attachment.file(this.file, this.name) : isImage = false;
}
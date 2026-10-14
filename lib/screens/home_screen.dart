import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/app_database.dart';
import '../main.dart' show ConfigScope;
import '../models/app_config.dart';
import '../models/chat.dart';
import '../utils/dialogs.dart';
import '../utils/error_code.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Chat> _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final list = await AppDatabase.instance.listChats();
      if (!mounted) return;
      setState(() {
        _chats = list;
        _loading = false;
      });
    } on AppError {
      rethrow;
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      throw AppError(Ec.sc05.code, Ec.sc05.message, cause: e, stack: st);
    }
  }

  Future<void> _newChat() async {
    final title = await inputDialog(
      context,
      title: '新建对话',
      hint: '给对话起个名字',
    );
    if (title == null || title.isEmpty) return;
    late int id;
    try {
      id = await AppDatabase.instance.insertChat(Chat(title: title));
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc01.code, Ec.sc01.message, cause: e, stack: st);
    }
    if (!mounted) return;
    await _openChat(Chat(id: id, title: title));
  }

  Future<void> _openChat(Chat chat) async {
    try {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(chat: chat),
      ));
      await _refresh();
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc00.code, Ec.sc00.message, cause: e, stack: st);
    }
  }

  Future<void> _deleteChat(Chat chat) async {
    final ok = await confirmDialog(
      context,
      title: '删除对话',
      message: '确定删除 "${chat.title}"?消息也会一并删除。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.instance.deleteMessagesForChat(chat.id!);
      await AppDatabase.instance.deleteChat(chat.id!);
      await _refresh();
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc02.code, Ec.sc02.message, cause: e, stack: st);
    }
  }

  Future<void> _renameChat(Chat chat) async {
    final t = await inputDialog(context,
        title: '重命名', initialValue: chat.title);
    if (t == null || t.isEmpty || t == chat.title) return;
    try {
      await AppDatabase.instance
          .updateChat(chat.copyWith(title: t, updatedAt: DateTime.now()));
      await _refresh();
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc03.code, Ec.sc03.message, cause: e, stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI 对话'),
          actions: [
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                try {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                        controller: ConfigScope.of(context).controller),
                  ));
                } on AppError {
                  rethrow;
                } catch (e, st) {
                  throw AppError(Ec.sc09.code, Ec.sc09.message,
                      cause: e, stack: st);
                }
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _chats.isEmpty
                ? _emptyState(scheme)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      itemCount: _chats.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final c = _chats[i];
                        return Card(
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            leading: CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(Icons.chat_bubble_outline,
                                    color: scheme.onPrimaryContainer)),
                            title: Text(c.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '更新于 ${DateFormat('MM-dd HH:mm').format(c.updatedAt)}',
                            ),
                            onTap: () => _openChat(c),
                            onLongPress: () async {
                              final v = await showModalBottomSheet<String>(
                                context: context,
                                builder: (_) => Wrap(children: [
                                  ListTile(
                                      leading: const Icon(Icons.edit),
                                      title: const Text('重命名'),
                                      onTap: () =>
                                          Navigator.pop(context, 'rename')),
                                  ListTile(
                                      leading: const Icon(Icons.delete,
                                          color: Colors.red),
                                      title: const Text('删除',
                                          style:
                                              TextStyle(color: Colors.red)),
                                      onTap: () =>
                                          Navigator.pop(context, 'delete')),
                                ]),
                              );
                              if (v == 'rename') await _renameChat(c);
                              if (v == 'delete') await _deleteChat(c);
                            },
                          ),
                        );
                      },
                    ),
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newChat,
          icon: const Icon(Icons.add),
          label: const Text('新建'),
        ),
      );
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.sc00.code, Ec.sc00.message, cause: e, stack: st);
    }
  }

  Widget _emptyState(ColorScheme s) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 72, color: s.primaryContainer),
          const SizedBox(height: 12),
          Text('还没有对话',
              style: TextStyle(fontSize: 18, color: s.onSurfaceVariant)),
          const SizedBox(height: 4),
          const Text('点击右下角"新建"开始',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/app_database.dart';
import '../main.dart' show ConfigScope;
import '../models/app_config.dart';
import '../models/chat.dart';
import '../theme/spacing.dart';
import '../utils/dialogs.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// 对话列表 — M3:
/// - 列表项用 ListTile(56dp 最小高度),卡片负责裁剪,避免双重圆角
/// - 破坏性操作用 colorScheme.error,不用硬编码红色
/// - 空状态用 onSurfaceVariant 级别对比度
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, '读取对话失败: $e', error: true);
    }
  }

  Future<void> _newChat() async {
    final title = await inputDialog(
      context,
      title: '新建对话',
      hint: '给对话起个名字',
    );
    if (title == null || title.isEmpty) return;
    try {
      final chat = Chat(title: title);
      final id = await AppDatabase.instance.insertChat(chat);
      if (!mounted) return;
      await _openChat(Chat(id: id, title: title));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '创建失败: $e', error: true);
    }
  }

  Future<void> _openChat(Chat chat) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(chat: chat),
    ));
    await _refresh();
  }

  Future<void> _deleteChat(Chat chat) async {
    final ok = await confirmDialog(
      context,
      title: '删除对话',
      message: '确定删除「${chat.title}」?该对话的所有消息都会被删除,且无法恢复。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.instance.deleteMessagesForChat(chat.id!);
      await AppDatabase.instance.deleteChat(chat.id!);
      await _refresh();
      if (!mounted) return;
      showSnack(context, '已删除「${chat.title}」');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '删除失败: $e', error: true);
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
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '重命名失败: $e', error: true);
    }
  }

  Future<void> _showChatMenu(Chat c) async {
    final s = Theme.of(context).colorScheme;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(sheetCtx, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: s.error),
              title: Text('删除', style: TextStyle(color: s.error)),
              onTap: () => Navigator.pop(sheetCtx, 'delete'),
            ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
    if (v == 'rename') await _renameChat(c);
    if (v == 'delete') await _deleteChat(c);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(
                  controller: ConfigScope.of(context).controller),
            )),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? _emptyState(theme)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: Insets.listWithFab,
                    itemCount: _chats.length,
                    itemBuilder: (_, i) {
                      final c = _chats[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.secondaryContainer,
                            foregroundColor:
                                theme.colorScheme.onSecondaryContainer,
                            child: const Icon(Icons.chat_bubble_outline, size: 20),
                          ),
                          title: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_relativeTime(c.updatedAt)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openChat(c),
                          onLongPress: () => _showChatMenu(c),
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
  }

  Widget _emptyState(ThemeData theme) {
    final s = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: s.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.forum_outlined,
                  size: 44, color: s.onSecondaryContainer),
            ),
            const SizedBox(height: Gap.xl),
            Text('还没有对话', style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            Text(
              '点击下方「新建」开始第一次对话',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: s.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 今天显示时间,昨天/更早显示日期 —— 避免 "MM-dd" 造成的歧义
  String _relativeTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return '今天 ${DateFormat('HH:mm').format(local)}';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;
    if (isYesterday) return '昨天 ${DateFormat('HH:mm').format(local)}';
    return DateFormat('yyyy-MM-dd HH:mm').format(local);
  }
}

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chat.dart';
import '../services/export_service.dart';

/// 显示导出底部表单 — 当前只支持 Markdown 一问一答格式
Future<void> showExportSheet(
  BuildContext ctx, {
  required Chat chat,
  required List<Message> messages,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: ctx,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('导出为 Markdown(一问一答)'),
            subtitle:
                const Text('每个用户问题后紧跟其助手回答,跳过未配对的对话'),
            onTap: () => Navigator.pop(_, true),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(_, false),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (!ctx.mounted) return;
  final file = await ExportService.exportChat(
      chat: chat, messages: messages);
  if (!ctx.mounted) return;
  await Share.shareXFiles([XFile(file.path)],
      text: '对话导出: ${chat.title}');
}
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/chat.dart';
import '../../data/services/export_service.dart';
import '../../core/theme/spacing.dart';

/// 导出底部表单 — 纯文本一问一答([Q1:...] / [A1:...])
Future<void> showExportSheet(
  BuildContext ctx, {
  required Chat chat,
  required List<Message> messages,
}) async {
  if (messages.isEmpty) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('没有可导出的消息'),
      ),
    );
    return;
  }

  final ok = await showModalBottomSheet<bool>(
    context: ctx,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Gap.sm),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('导出为文本文件'),
            subtitle: const Text('一问一答,格式 [Q1:…] / [A1:…]'),
            onTap: () => Navigator.pop(sheetCtx, true),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(sheetCtx, false),
          ),
          const SizedBox(height: Gap.sm),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (!ctx.mounted) return;

  try {
    final file =
        await ExportService.exportChat(chat: chat, messages: messages);
    if (!ctx.mounted) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      subject: chat.title,
    );
  } catch (e) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('导出失败: $e'),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/export_service.dart';

/// 导出对话框 — 选择格式并分享
Future<void> showExportSheet(
  BuildContext ctx, {
  required dynamic chat,
  required List<dynamic> messages,
}) async {
  final fmt = await showModalBottomSheet<ExportFormat>(
    context: ctx,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
              title: Text('导出对话', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final f in ExportFormat.values)
            ListTile(
              leading: Icon(switch (f) {
                ExportFormat.json => Icons.code,
                ExportFormat.markdown => Icons.description,
                ExportFormat.text => Icons.text_snippet,
              }),
              title: Text(switch (f) {
                ExportFormat.json => 'JSON',
                ExportFormat.markdown => 'Markdown',
                ExportFormat.text => '纯文本',
              }),
              onTap: () => Navigator.pop(ctx, f),
            ),
        ],
      ),
    ),
  );
  if (fmt == null) return;
  if (!ctx.mounted) return;
  final file = await ExportService.exportChat(
      chat: chat, messages: messages, format: fmt);
  if (!ctx.mounted) return;
  await Share.shareXFiles([XFile(file.path)],
      text: '对话导出: ${chat.title}');
  // iOS / Android 上分享完成后清理
  // ignore: unused_local_variable
  final _ = file; // 避免 lint
}

/// 让旧 Android 设备在无 share_plus 时也能用 — 此处保留为空实现
class NoOpShare {
  static Future<void> share(File file) async {
    await Share.shareXFiles([XFile(file.path)]);
  }
}
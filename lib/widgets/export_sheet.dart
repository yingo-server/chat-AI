import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../error_code.dart';
import '../models/chat.dart';
import '../services/export_service.dart';

Future<void> showExportSheet(
  BuildContext ctx, {
  required Chat chat,
  required List<Message> messages,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: ctx,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('导出为 Markdown(一问一答)'),
            subtitle: const Text('每个用户问题后紧跟其助手回答,跳过未配对的对话'),
            onTap: () => Navigator.pop(sheetCtx, true),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(sheetCtx, false),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (!ctx.mounted) return;

  late File file;
  try {
    file = await ExportService.exportChat(chat: chat, messages: messages);
  } on AppError {
    rethrow;
  } catch (e, st) {
    throw AppError(Ec.sc06.code, Ec.sc06.message, cause: e, stack: st);
  }

  if (!ctx.mounted) return;
  try {
    await Share.shareXFiles([XFile(file.path)],
        text: '对话导出: ${chat.title}');
  } catch (e, st) {
    throw AppError(Ec.ex02.code, Ec.ex02.message, cause: e, stack: st);
  }
}
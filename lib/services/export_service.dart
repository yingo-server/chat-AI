import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';

enum ExportFormat { json, markdown, text }

class ExportService {
  /// 把单个对话导出到临时文件并返回 File 对象
  static Future<File> exportChat({
    required Chat chat,
    required List<Message> messages,
    required ExportFormat format,
  }) async {
    final tmp = await getTemporaryDirectory();
    final safe = _sanitize(chat.title);
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final ext = switch (format) {
      ExportFormat.json => 'json',
      ExportFormat.markdown => 'md',
      ExportFormat.text => 'txt',
    };
    final file = File('${tmp.path}/${safe}_$ts.$ext');

    switch (format) {
      case ExportFormat.json:
        await file.writeAsString(_toJson(chat, messages));
        break;
      case ExportFormat.markdown:
        await file.writeAsString(_toMarkdown(chat, messages));
        break;
      case ExportFormat.text:
        await file.writeAsString(_toText(chat, messages));
        break;
    }
    return file;
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  static String _toJson(Chat chat, List<Message> messages) {
    final payload = {
      'title': chat.title,
      'createdAt': chat.createdAt.toIso8601String(),
      'updatedAt': chat.updatedAt.toIso8601String(),
      'systemPromptId': chat.systemPromptId,
      'extraSystemPrompt': chat.extraSystemPrompt,
      'messages': messages
          .where((m) => m.role != MessageRole.compressed)
          .map((m) => {
                'role': m.role == MessageRole.user
                    ? 'user'
                    : m.role == MessageRole.assistant
                        ? 'assistant'
                        : 'system',
                'content': m.content,
                'createdAt': m.createdAt.toIso8601String(),
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static String _toMarkdown(Chat chat, List<Message> messages) {
    final buf = StringBuffer();
    buf.writeln('# ${chat.title}');
    buf.writeln(
        '> 创建: ${DateFormat('yyyy-MM-dd HH:mm').format(chat.createdAt)} · '
            '更新: ${DateFormat('yyyy-MM-dd HH:mm').format(chat.updatedAt)}');
    buf.writeln();
    for (final m in messages.where((m) => m.role != MessageRole.compressed)) {
      final ts = DateFormat('yyyy-MM-dd HH:mm').format(m.createdAt);
      final label = switch (m.role) {
        MessageRole.user => '👤 用户',
        MessageRole.assistant => '🤖 助手',
        _ => '⚙️ 系统',
      };
      buf.writeln('## $label · $ts');
      buf.writeln();
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }

  static String _toText(Chat chat, List<Message> messages) {
    final buf = StringBuffer();
    buf.writeln('标题: ${chat.title}');
    buf.writeln('---');
    for (final m in messages.where((m) => m.role != MessageRole.compressed)) {
      final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(m.createdAt);
      final label = switch (m.role) {
        MessageRole.user => '用户',
        MessageRole.assistant => '助手',
        _ => '系统',
      };
      buf.writeln('[$ts] $label:');
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }
}
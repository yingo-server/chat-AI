import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';

/// 仅支持 Markdown 导出。格式:严格一问一答。
/// Q: 时间 · 用户
/// A: 时间 · 助手
class ExportService {
  /// 导出整个对话到临时文件,返回 [File]。
  static Future<File> exportChat({
    required Chat chat,
    required List<Message> messages,
  }) async {
    final tmp = await getTemporaryDirectory();
    final safe = _sanitize(chat.title);
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${tmp.path}/${safe}_$ts.md');
    await file.writeAsString(_toMarkdown(chat, messages));
    return file;
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_').trim();

  /// 严格一问一答:遍历 messages,user 后必跟一条 assistant(若有),否则跳过该 user。
  static String _toMarkdown(Chat chat, List<Message> messages) {
    final filtered =
        messages.where((m) => m.role == MessageRole.user ||
            m.role == MessageRole.assistant).toList();

    final buf = StringBuffer();
    buf.writeln('# ${chat.title}');
    buf.writeln();
    buf.writeln(
        '> 创建: ${DateFormat('yyyy-MM-dd HH:mm').format(chat.createdAt)} · '
            '更新: ${DateFormat('yyyy-MM-dd HH:mm').format(chat.updatedAt)}');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    for (var i = 0; i < filtered.length; i++) {
      final m = filtered[i];
      final time = DateFormat('yyyy-MM-dd HH:mm').format(m.createdAt);
      if (m.role == MessageRole.user) {
        buf.writeln('## ❓ 问题');
        buf.writeln();
        buf.writeln('**时间**: $time');
        buf.writeln();
        buf.writeln(m.content.trim());
        buf.writeln();
        // 紧跟助手回复(若列表中下一条是 assistant)
        if (i + 1 < filtered.length &&
            filtered[i + 1].role == MessageRole.assistant) {
          final a = filtered[i + 1];
          final aTime = DateFormat('yyyy-MM-dd HH:mm').format(a.createdAt);
          buf.writeln();
          buf.writeln('## ✅ 回答');
          buf.writeln();
          buf.writeln('**时间**: $aTime');
          buf.writeln();
          buf.writeln(a.content.trim());
          buf.writeln();
          i++; // 跳过已消费的 assistant
        }
        buf.writeln('---');
        buf.writeln();
      }
    }
    return buf.toString();
  }
}
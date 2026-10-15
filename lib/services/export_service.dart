import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';

/// 纯文本导出。严格一问一答,紧凑格式:
///
///   标题: xxx
///   创建: 2026-10-15 22:03
///   导出: 2026-10-15 22:10
///
///   [Q1:你好]
///   [A1:你好,有什么可以帮你?]
///
///   [Q2:...]
///   [A2:...]
///
/// 不使用 Markdown 标记、不使用 emoji。
class ExportService {
  static Future<File> exportChat({
    required Chat chat,
    required List<Message> messages,
  }) async {
    final tmp = await getTemporaryDirectory();
    final safe = _sanitize(chat.title);
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${tmp.path}/${safe}_$ts.txt');
    await file.writeAsString(_toTxt(chat, messages));
    return file;
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_').trim();

  static String _toTxt(Chat chat, List<Message> messages) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final filtered = messages
        .where((m) =>
            m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();

    final buf = StringBuffer();
    buf.writeln('标题: ${chat.title}');
    buf.writeln('创建: ${df.format(chat.createdAt)}');
    buf.writeln('导出: ${df.format(DateTime.now())}');
    buf.writeln();

    var n = 0;
    for (var i = 0; i < filtered.length; i++) {
      final m = filtered[i];
      if (m.role != MessageRole.user) continue; // 仅从用户提问起算一轮
      n++;
      final q = m.content.trim();
      // 答案 = 紧随其后的第一条助手消息(若有)
      String a = '';
      if (i + 1 < filtered.length &&
          filtered[i + 1].role == MessageRole.assistant) {
        a = filtered[i + 1].content.trim();
        i++; // 消费该助手消息
      }
      buf.writeln('[Q$n: $q]');
      if (a.isNotEmpty) {
        buf.writeln('[A$n: $a]');
      }
      buf.writeln();
    }
    return buf.toString();
  }
}

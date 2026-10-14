import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';
import '../utils/error_code.dart';

class ExportService {
  /// 抛 AppError(Ec.ex0x)
  static Future<File> exportChat({
    required Chat chat,
    required List<Message> messages,
  }) async {
    Directory tmp;
    try {
      tmp = await getTemporaryDirectory();
    } catch (e, st) {
      throw AppError(Ec.ex00.code, Ec.ex00.message, cause: e, stack: st);
    }
    final safe = _sanitize(chat.title);
    if (safe.isEmpty) {
      throw AppError(Ec.ex04.code, Ec.ex04.message);
    }
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${tmp.path}/${safe}_$ts.md');
    try {
      await file.writeAsString(_toMarkdown(chat, messages));
      return file;
    } catch (e, st) {
      throw AppError(Ec.ex01.code, Ec.ex01.message, cause: e, stack: st);
    }
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_').trim();

  /// 严格一问一答
  static String _toMarkdown(Chat chat, List<Message> messages) {
    try {
      final filtered = messages
          .where((m) => m.role == MessageRole.user ||
              m.role == MessageRole.assistant)
          .toList();
      if (filtered.isEmpty) {
        throw AppError(Ec.ex05.code, Ec.ex05.message);
      }
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
            i++;
          }
          buf.writeln('---');
          buf.writeln();
        }
      }
      return buf.toString();
    } on AppError {
      rethrow;
    } catch (e, st) {
      throw AppError(Ec.ex01.code, Ec.ex01.message, cause: e, stack: st);
    }
  }
}
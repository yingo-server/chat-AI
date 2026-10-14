import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat.dart';
import '../utils/error_code.dart';

/// SQLite 持久层 — 所有失败抛 AppError(带错误码)
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _database;
  Future<Database> get db async {
    if (_database != null) return _database!;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final path = p.join(docs.path, 'ai_chat.db');
      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, v) async {
          try {
            await db.execute('''
              CREATE TABLE chats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                system_prompt_id TEXT NOT NULL DEFAULT 'default',
                extra_system_prompt TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                chat_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                token_count INTEGER,
                compressed INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
              )
            ''');
            await db.execute(
                'CREATE INDEX idx_messages_chat ON messages(chat_id, created_at)');
          } catch (e, st) {
            throw AppError(Ec.db00.code, Ec.db00.message, cause: e, stack: st);
          }
        },
      );
      return _database!;
    } catch (e, st) {
      if (e is AppError) rethrow;
      throw AppError(Ec.db00.code, Ec.db00.message, cause: e, stack: st);
    }
  }

  // ---------- Chats ----------

  /// 抛 AppError(Ec.db01) 失败
  Future<int> insertChat(Chat chat) async {
    try {
      final d = await db;
      return await d.insert('chats', chat.toMap()..remove('id'));
    } catch (e, st) {
      throw AppError(Ec.db01.code, Ec.db01.message, cause: e, stack: st);
    }
  }

  /// 0=成功,Ec.md06=无效 chat id
  Future<int> updateChat(Chat chat) async {
    if (chat.id == null) return Ec.md06.code;
    try {
      final d = await db;
      await d.update('chats', chat.toMap(),
          where: 'id = ?', whereArgs: [chat.id]);
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db02.code, Ec.db02.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> deleteChat(int chatId) async {
    try {
      final d = await db;
      await d.delete('chats', where: 'id = ?', whereArgs: [chatId]);
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db03.code, Ec.db03.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> touchChat(int chatId) async {
    try {
      final d = await db;
      await d.update('chats', {'updated_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [chatId]);
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db11.code, Ec.db11.message, cause: e, stack: st);
    }
  }

  /// 抛 AppError(Ec.db04) 失败
  Future<List<Chat>> listChats() async {
    try {
      final d = await db;
      final rows = await d.query('chats', orderBy: 'updated_at DESC');
      return rows.map(Chat.fromMap).toList();
    } catch (e, st) {
      throw AppError(Ec.db04.code, Ec.db04.message, cause: e, stack: st);
    }
  }

  /// 抛 AppError(Ec.db05) 失败
  Future<Chat?> getChat(int chatId) async {
    try {
      final d = await db;
      final rows =
          await d.query('chats', where: 'id = ?', whereArgs: [chatId], limit: 1);
      if (rows.isEmpty) return null;
      return Chat.fromMap(rows.first);
    } catch (e, st) {
      throw AppError(Ec.db05.code, Ec.db05.message, cause: e, stack: st);
    }
  }

  // ---------- Messages ----------

  /// 抛 AppError(Ec.db06) 失败
  Future<int> insertMessage(Message m) async {
    try {
      final d = await db;
      return await d.insert('messages', m.toMap()..remove('id'));
    } catch (e, st) {
      throw AppError(Ec.db06.code, Ec.db06.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> updateMessageContent(int id, String content) async {
    try {
      final d = await db;
      await d.update('messages', {'content': content},
          where: 'id = ?', whereArgs: [id]);
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db10.code, Ec.db10.message, cause: e, stack: st);
    }
  }

  /// 抛 AppError(Ec.db07) 失败
  Future<List<Message>> listMessages(int chatId,
      {bool includeCompressed = true}) async {
    try {
      final d = await db;
      final where = includeCompressed
          ? 'chat_id = ?'
          : 'chat_id = ? AND compressed = 0';
      final rows = await d.query('messages',
          where: where,
          whereArgs: [chatId],
          orderBy: 'created_at ASC, id ASC');
      return rows.map(Message.fromMap).toList();
    } catch (e, st) {
      throw AppError(Ec.db07.code, Ec.db07.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> deleteMessagesForChat(int chatId) async {
    try {
      final d = await db;
      await d.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db08.code, Ec.db08.message, cause: e, stack: st);
    }
  }

  /// 0=成功
  Future<int> markMessagesCompressed(Iterable<int> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final d = await db;
      final placeholders = List.filled(ids.length, '?').join(',');
      await d.rawUpdate(
        'UPDATE messages SET compressed = 1 WHERE id IN ($placeholders)',
        ids.toList(),
      );
      return 0;
    } catch (e, st) {
      throw AppError(Ec.db09.code, Ec.db09.message, cause: e, stack: st);
    }
  }
}
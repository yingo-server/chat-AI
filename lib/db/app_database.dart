import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat.dart';

/// SQLite 持久层 — 应用文档目录下的 ai_chat.db
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _database;
  Future<Database> get db async => _database ??= await _open();

  Future<Database> _open() async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'ai_chat.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
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
      },
    );
  }

  // ---------- Chats ----------

  Future<int> insertChat(Chat chat) async {
    final d = await db;
    return d.insert('chats', chat.toMap()..remove('id'));
  }

  Future<void> updateChat(Chat chat) async {
    if (chat.id == null) return;
    final d = await db;
    await d.update('chats', chat.toMap(),
        where: 'id = ?', whereArgs: [chat.id]);
  }

  Future<void> touchChat(int chatId) async {
    final d = await db;
    await d.update('chats', {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [chatId]);
  }

  Future<void> deleteChat(int chatId) async {
    final d = await db;
    await d.delete('chats', where: 'id = ?', whereArgs: [chatId]);
  }

  Future<List<Chat>> listChats() async {
    final d = await db;
    final rows = await d.query('chats', orderBy: 'updated_at DESC');
    return rows.map(Chat.fromMap).toList();
  }

  Future<Chat?> getChat(int chatId) async {
    final d = await db;
    final rows =
        await d.query('chats', where: 'id = ?', whereArgs: [chatId], limit: 1);
    if (rows.isEmpty) return null;
    return Chat.fromMap(rows.first);
  }

  // ---------- Messages ----------

  Future<int> insertMessage(Message m) async {
    final d = await db;
    return d.insert('messages', m.toMap()..remove('id'));
  }

  Future<void> updateMessageContent(int id, String content) async {
    final d = await db;
    await d.update('messages', {'content': content},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Message>> listMessages(int chatId,
      {bool includeCompressed = true}) async {
    final d = await db;
    final where = includeCompressed
        ? 'chat_id = ?'
        : 'chat_id = ? AND compressed = 0';
    final rows = await d.query('messages',
        where: where,
        whereArgs: [chatId],
        orderBy: 'created_at ASC, id ASC');
    return rows.map(Message.fromMap).toList();
  }

  Future<void> markMessagesCompressed(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await d.rawUpdate(
      'UPDATE messages SET compressed = 1 WHERE id IN ($placeholders)',
      ids.toList(),
    );
  }

  Future<void> deleteMessagesForChat(int chatId) async {
    final d = await db;
    await d.delete('messages', where: 'chat_id = ?', whereArgs: [chatId]);
  }
}
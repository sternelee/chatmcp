import 'package:chatmcp/dao/libsql_base_dao.dart';
import 'package:chatmcp/dao/chat_message.dart';
import 'package:chatmcp/dao/libsql_database.dart';
import 'package:chatmcp/llm/model.dart' as llm_model;

/// Chat entity model
class Chat {
  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Chat({
    this.id,
    required this.title,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON (database row)
  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as int?,
      title: json['title'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// Get chat messages for this chat
  Future<List<llm_model.ChatMessage>> getChatMessages() async {
    if (id == null) return [];

    // Use a simple DAO approach with the original DbChatMessage class
    final messageDao = _LibSqlMessageDao();
    final chatMessages = await messageDao.findByColumn(
      'chatId',
      id!,
      orderBy: 'createdAt ASC',
    );

    return chatMessages.map((e) => llm_model.ChatMessage.fromDb(e)).toList();
  }

  /// Update title and timestamp
  Chat copyWithTitle(String newTitle) {
    return Chat(
      id: id,
      title: newTitle,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'Chat{id: $id, title: $title, createdAt: $createdAt, updatedAt: $updatedAt}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Chat &&
        other.id == id &&
        other.title == title &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode;
  }
}

/// Chat DAO using libsql_dart
class LibSqlChatDao extends LibSqlBaseDao<Chat> {
  static final LibSqlChatDao _instance = LibSqlChatDao._internal();
  factory LibSqlChatDao() => _instance;
  LibSqlChatDao._internal() : super('chat');

  @override
  Chat fromJson(Map<String, dynamic> json) => Chat.fromJson(json);

  @override
  Map<String, dynamic> toJson(Chat entity) => entity.toJson();

  
  /// Get all chats ordered by creation date (newest first)
  Future<List<Chat>> getAllChats({int? limit, int? offset}) async {
    return await query(
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Search chats by title
  Future<List<Chat>> searchChats(String query, {int? limit}) async {
    return await rawQuery(
      'SELECT * FROM $tableName WHERE title LIKE ? ORDER BY createdAt DESC${limit != null ? ' LIMIT $limit' : ''}',
      ['%$query%'],
    );
  }

  /// Get chats created within date range
  Future<List<Chat>> getChatsByDateRange(DateTime start, DateTime end) async {
    return await query(
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'createdAt DESC',
    );
  }

  /// Update chat title
  Future<int> updateTitle(int id, String newTitle) async {
    return await updateWhere(
      {'title': newTitle, 'updatedAt': DateTime.now().toIso8601String()},
      'id = ?',
      [id],
    );
  }

  /// Get chat statistics
  Future<Map<String, dynamic>> getChatStats() async {
    final totalChats = await count();

    // Get message count per chat
    final messageStats = await client.query('''
      SELECT
        c.id,
        c.title,
        COUNT(cm.id) as message_count,
        c.createdAt
      FROM $tableName c
      LEFT JOIN chat_message cm ON c.id = cm.chatId
      GROUP BY c.id, c.title, c.createdAt
      ORDER BY message_count DESC
    ''');

    return {
      'totalChats': totalChats,
      'messageStats': messageStats.map((row) => {
        'chatId': row['id'],
        'title': row['title'],
        'messageCount': row['message_count'],
        'createdAt': row['createdAt'],
      }).toList(),
    };
  }

  /// Delete chat and all its messages (cascade)
  Future<int> deleteChatWithMessages(int id) async {
    return await LibSqlDatabase.instance.transaction((txn) async {
      // First delete all messages
      await client.execute('DELETE FROM chat_message WHERE chatId = ?', positional: [id]);

      // Then delete the chat
      await client.execute('DELETE FROM $tableName WHERE id = ?', positional: [id]);

      return 1;
    });
  }

  /// Get recent chats with message count
  Future<List<Map<String, dynamic>>> getRecentChatsWithMessageCount({int limit = 10}) async {
    final results = await client.query('''
      SELECT
        c.*,
        COUNT(cm.id) as message_count
      FROM $tableName c
      LEFT JOIN chat_message cm ON c.id = cm.chatId
      GROUP BY c.id
      ORDER BY c.updatedAt DESC
      LIMIT ?
    ''', positional: [limit]);

    return results;
  }

  /// Backup chats to JSON
  Future<List<Map<String, dynamic>>> backupChats() async {
    final chats = await getAllChats();
    return chats.map((chat) => chat.toJson()).toList();
  }

  /// Restore chats from JSON
  Future<int> restoreChats(List<Map<String, dynamic>> chatData) async {
    if (chatData.isEmpty) return 0;

    final chats = chatData.map((json) => Chat.fromJson(json)).toList();
    await batchInsertOrReplace(chats);

    return chats.length;
  }
}

/// Simple message DAO for libsql that uses the original DbChatMessage class
class _LibSqlMessageDao extends LibSqlBaseDao<DbChatMessage> {
  _LibSqlMessageDao() : super('chat_message');

  @override
  DbChatMessage fromJson(Map<String, dynamic> json) {
    return DbChatMessage(
      id: json['id'] as int?,
      chatId: json['chatId'] as int? ?? 0,
      messageId: json['messageId'] as String? ?? '',
      parentMessageId: json['parentMessageId'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  Map<String, dynamic> toJson(DbChatMessage entity) => entity.toJson();
}
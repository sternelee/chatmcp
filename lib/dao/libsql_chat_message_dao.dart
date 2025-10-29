import 'package:uuid/uuid.dart';
import 'package:chatmcp/dao/libsql_base_dao.dart';
import 'package:chatmcp/dao/libsql_database.dart';

/// ChatMessage entity model for database storage
class DbChatMessage {
  final int? id;
  final int chatId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String messageId;
  final String parentMessageId;

  DbChatMessage({
    this.id,
    required this.chatId,
    required this.body,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? messageId,
    this.parentMessageId = '',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messageId = messageId ?? const Uuid().v4();

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'chatId': chatId,
      'messageId': messageId,
      'parentMessageId': parentMessageId,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON (database row)
  factory DbChatMessage.fromJson(Map<String, dynamic> json) {
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

  /// Create a copy with updated body and timestamp
  DbChatMessage copyWithBody(String newBody) {
    return DbChatMessage(
      id: id,
      chatId: chatId,
      body: newBody,
      messageId: messageId,
      parentMessageId: parentMessageId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Create a reply message
  DbChatMessage createReply(String replyBody) {
    return DbChatMessage(
      chatId: chatId,
      body: replyBody,
      parentMessageId: messageId,
    );
  }

  @override
  String toString() {
    return 'DbChatMessage{id: $id, chatId: $chatId, messageId: $messageId, parentMessageId: $parentMessageId, createdAt: $createdAt}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DbChatMessage &&
        other.id == id &&
        other.chatId == chatId &&
        other.messageId == messageId &&
        other.parentMessageId == parentMessageId &&
        other.body == body &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        chatId.hashCode ^
        messageId.hashCode ^
        parentMessageId.hashCode ^
        body.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode;
  }
}

/// ChatMessage DAO using libsql_dart
class LibSqlChatMessageDao extends LibSqlBaseDao<DbChatMessage> {
  static final LibSqlChatMessageDao _instance = LibSqlChatMessageDao._internal();
  factory LibSqlChatMessageDao() => _instance;
  LibSqlChatMessageDao._internal() : super('chat_message');

  @override
  DbChatMessage fromJson(Map<String, dynamic> json) => DbChatMessage.fromJson(json);

  @override
  Map<String, dynamic> toJson(DbChatMessage entity) => entity.toJson();

  
  /// Get all messages for a chat ordered by creation date
  Future<List<DbChatMessage>> getMessagesForChat(int chatId, {int? limit, int? offset}) async {
    return await query(
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt ASC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get message by messageId
  Future<DbChatMessage?> findByMessageId(String messageId) async {
    final results = await query(
      where: 'messageId = ?',
      whereArgs: [messageId],
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// Get messages for a chat by parentMessageId (conversation thread)
  Future<List<DbChatMessage>> getThread(int chatId, String parentMessageId) async {
    return await query(
      where: 'chatId = ? AND parentMessageId = ?',
      whereArgs: [chatId, parentMessageId],
      orderBy: 'createdAt ASC',
    );
  }

  /// Delete all messages for a chat
  Future<int> deleteMessagesForChat(int chatId) async {
    return await deleteWhere('chatId = ?', [chatId]);
  }

  /// Delete a message thread (all replies to a message)
  Future<int> deleteMessageThread(String parentMessageId) async {
    return await LibSqlDatabase.instance.transaction((txn) async {
      // Delete all replies first
      await client.execute('DELETE FROM $tableName WHERE parentMessageId = ?', positional: [parentMessageId]);

      // Delete the parent message
      await client.execute('DELETE FROM $tableName WHERE messageId = ?', positional: [parentMessageId]);

      return 1;
    });
  }

  /// Get message count for a chat
  Future<int> getMessageCountForChat(int chatId) async {
    return await count(where: 'chatId = ?', whereArgs: [chatId]);
  }

  /// Search messages within a chat
  Future<List<DbChatMessage>> searchMessagesInChat(int chatId, String query, {int? limit}) async {
    return await rawQuery(
      'SELECT * FROM $tableName WHERE chatId = ? AND body LIKE ? ORDER BY createdAt ASC${limit != null ? ' LIMIT $limit' : ''}',
      [chatId, '%$query%'],
    );
  }

  /// Get messages created within date range for a chat
  Future<List<DbChatMessage>> getMessagesByDateRange(
    int chatId,
    DateTime start,
    DateTime end,
  ) async {
    return await query(
      where: 'chatId = ? AND createdAt >= ? AND createdAt <= ?',
      whereArgs: [chatId, start.toIso8601String(), end.toIso8601String()],
      orderBy: 'createdAt ASC',
    );
  }

  /// Get the latest message for a chat
  Future<DbChatMessage?> getLatestMessage(int chatId) async {
    return await first(
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt DESC',
    );
  }

  /// Get the first message for a chat
  Future<DbChatMessage?> getFirstMessage(int chatId) async {
    return await first(
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt ASC',
    );
  }

  /// Update message body
  Future<int> updateMessageBody(int id, String newBody) async {
    return await updateWhere(
      {'body': newBody, 'updatedAt': DateTime.now().toIso8601String()},
      'id = ?',
      [id],
    );
  }

  /// Get message statistics for a chat
  Future<Map<String, dynamic>> getMessageStats(int chatId) async {
    final messageCount = await count(where: 'chatId = ?', whereArgs: [chatId]);

    // Get character count and message size distribution
    final stats = await LibSqlDatabase.instance.client.query('''
      SELECT
        COUNT(*) as total_messages,
        SUM(LENGTH(body)) as total_characters,
        AVG(LENGTH(body)) as avg_message_length,
        MIN(LENGTH(body)) as min_message_length,
        MAX(LENGTH(body)) as max_message_length,
        MIN(createdAt) as first_message_time,
        MAX(createdAt) as last_message_time
      FROM $tableName
      WHERE chatId = ?
    ''', positional: [chatId]);

    final stat = stats.first;

    return {
      'messageCount': messageCount,
      'totalMessages': stat['total_messages'] as int? ?? 0,
      'totalCharacters': stat['total_characters'] as int? ?? 0,
      'avgMessageLength': (stat['avg_message_length'] as double?)?.round() ?? 0,
      'minMessageLength': stat['min_message_length'] as int? ?? 0,
      'maxMessageLength': stat['max_message_length'] as int? ?? 0,
      'firstMessageTime': stat['first_message_time'] as String?,
      'lastMessageTime': stat['last_message_time'] as String?,
    };
  }

  /// Get conversation tree structure for a chat
  Future<Map<String, dynamic>> getConversationTree(int chatId) async {
    final allMessages = await getMessagesForChat(chatId);

    // Build tree structure
    Map<String, dynamic> tree = {};
    Map<String, List<Map<String, dynamic>>> childrenMap = {};

    // First pass: collect all messages and organize by parent
    for (final message in allMessages) {
      final json = message.toJson();
      final parentId = message.parentMessageId.isEmpty ? 'root' : message.parentMessageId;

      if (!childrenMap.containsKey(parentId)) {
        childrenMap[parentId] = [];
      }
      childrenMap[parentId]!.add(json);
    }

    // Helper function to build tree recursively
    List<Map<String, dynamic>> buildChildren(String parentId) {
      if (!childrenMap.containsKey(parentId)) return [];

      return childrenMap[parentId]!.map((child) {
        final messageId = child['messageId'] as String;
        child['children'] = buildChildren(messageId);
        return child;
      }).toList();
    }

    // Build the tree starting from root messages
    tree['children'] = buildChildren('root');
    tree['totalMessages'] = allMessages.length;

    return tree;
  }

  /// Backup messages to JSON
  Future<List<Map<String, dynamic>>> backupMessages({int? chatId}) async {
    List<DbChatMessage> messages;

    if (chatId != null) {
      messages = await getMessagesForChat(chatId);
    } else {
      messages = await query(); // Get all messages
    }

    return messages.map((message) => message.toJson()).toList();
  }

  /// Restore messages from JSON
  Future<int> restoreMessages(List<Map<String, dynamic>> messageData) async {
    if (messageData.isEmpty) return 0;

    final messages = messageData.map((json) => DbChatMessage.fromJson(json)).toList();
    await batchInsertOrReplace(messages);

    return messages.length;
  }

  /// Bulk delete messages for multiple chats
  Future<int> deleteMessagesForChats(List<int> chatIds) async {
    if (chatIds.isEmpty) return 0;

    final placeholders = List.filled(chatIds.length, '?').join(',');
    return await deleteWhere('chatId IN ($placeholders)', chatIds);
  }

  /// Get orphaned messages (messages without valid chatId)
  Future<List<DbChatMessage>> getOrphanedMessages() async {
    return await rawQuery('''
      SELECT cm.* FROM $tableName cm
      LEFT JOIN chat c ON cm.chatId = c.id
      WHERE c.id IS NULL
      ORDER BY cm.createdAt ASC
    ''');
  }

  /// Clean up orphaned messages
  Future<int> cleanupOrphanedMessages() async {
    await rawExecute('''
      DELETE FROM $tableName WHERE chatId NOT IN (SELECT id FROM chat)
    ''');
    // libsql_dart doesn't provide affected rows count directly
    return 1;
  }
}
import 'package:chatmcp/dao/libsql_chat_dao.dart';
import 'package:chatmcp/dao/libsql_chat_message_dao.dart';
import 'package:chatmcp/llm/model.dart';
import 'package:chatmcp/repository/chat_repository.dart';
import 'package:chatmcp/config/pagination_config.dart';
import 'package:logging/logging.dart';

// Import the original Chat class for compatibility
import 'package:chatmcp/dao/chat.dart' as chat;
import 'package:chatmcp/dao/chat_message.dart' as msg;

/// Local chat repository using libsql_dart DAOs
class LibSqlChatRepository implements ChatRepository {
  final LibSqlChatDao _chatDao = LibSqlChatDao();
  final LibSqlChatMessageDao _chatMessageDao = LibSqlChatMessageDao();

  @override
  Future<ChatListResult> getChats({
    int page = 1, // 页码从 1 开始
    int pageSize = PaginationConfig.defaultPageSize,
    String? searchKeyword,
  }) async {
    try {
      // 转换为从 0 开始的 offset 计算
      final offset = (page - 1) * pageSize;

      // Get paginated results using the enhanced DAO
      final libsqlChats = await _chatDao.query(
        where: searchKeyword != null && searchKeyword.isNotEmpty ? 'title LIKE ?' : null,
        whereArgs: searchKeyword != null && searchKeyword.isNotEmpty ? ['%$searchKeyword%'] : null,
        orderBy: 'updatedAt DESC',
        limit: pageSize,
        offset: offset,
      );

      // Convert libsql_dart Chat models to original Chat models
      final chats = libsqlChats.map((libsqlChat) => chat.Chat(
        id: libsqlChat.id,
        title: libsqlChat.title,
        createdAt: libsqlChat.createdAt,
        updatedAt: libsqlChat.updatedAt,
      )).toList();

      // Get total count for pagination
      final total = await _chatDao.count(
        where: searchKeyword != null && searchKeyword.isNotEmpty ? 'title LIKE ?' : null,
        whereArgs: searchKeyword != null && searchKeyword.isNotEmpty ? ['%$searchKeyword%'] : null,
      );

      final hasMore = offset + pageSize < total;

      return ChatListResult(chats: chats, total: total, hasMore: hasMore);
    } catch (e) {
      Logger.root.severe('Failed to get chats: $e');
      rethrow;
    }
  }

  @override
  Future<List<chat.Chat>> getAllChats() async {
    try {
      final libsqlChats = await _chatDao.getAllChats();
      return libsqlChats.map((libsqlChat) => chat.Chat(
        id: libsqlChat.id,
        title: libsqlChat.title,
        createdAt: libsqlChat.createdAt,
        updatedAt: libsqlChat.updatedAt,
      )).toList();
    } catch (e) {
      Logger.root.severe('Failed to get all chats: $e');
      rethrow;
    }
  }

  @override
  Future<chat.Chat?> getChatById(int id) async {
    try {
      final libsqlChat = await _chatDao.findById(id);
      if (libsqlChat == null) return null;

      return chat.Chat(
        id: libsqlChat.id,
        title: libsqlChat.title,
        createdAt: libsqlChat.createdAt,
        updatedAt: libsqlChat.updatedAt,
      );
    } catch (e) {
      Logger.root.severe('Failed to get chat by ID $id: $e');
      rethrow;
    }
  }

  @override
  Future<chat.Chat> createChat(chat.Chat newChat, List<ChatMessage> messages) async {
    try {
      // Convert to libsql_dart Chat model
      final libsqlChat = Chat(
        id: newChat.id,
        title: newChat.title,
        createdAt: newChat.createdAt,
        updatedAt: newChat.updatedAt,
      );

      // Insert chat
      final chatId = await _chatDao.insert(libsqlChat);
      final createdChat = chat.Chat(
        id: chatId,
        title: libsqlChat.title,
        createdAt: libsqlChat.createdAt,
        updatedAt: libsqlChat.updatedAt,
      );

      // Insert messages if provided
      if (messages.isNotEmpty) {
        await addChatMessage(chatId, messages);
      }

      Logger.root.info('Created new chat with ID: $chatId');
      return createdChat;
    } catch (e) {
      Logger.root.severe('Failed to create chat: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateChat(chat.Chat chatToUpdate) async {
    try {
      if (chatToUpdate.id != null) {
        // Convert to libsql_dart Chat model
        final libsqlChat = Chat(
          id: chatToUpdate.id,
          title: chatToUpdate.title,
          createdAt: chatToUpdate.createdAt,
          updatedAt: chatToUpdate.updatedAt,
        );

        await _chatDao.update(libsqlChat, chatToUpdate.id!);
        Logger.root.info('Updated chat with ID: ${chatToUpdate.id}');
      } else {
        throw ArgumentError('Chat ID cannot be null for update');
      }
    } catch (e) {
      Logger.root.severe('Failed to update chat: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteChat(int id) async {
    try {
      // Delete all messages first (due to foreign key constraint, this will cascade)
      await _chatMessageDao.deleteMessagesForChat(id);

      // Delete the chat
      await _chatDao.delete(id);

      Logger.root.info('Deleted chat with ID: $id');
    } catch (e) {
      Logger.root.severe('Failed to delete chat with ID $id: $e');
      rethrow;
    }
  }

  @override
  Future<void> addChatMessage(int chatId, List<ChatMessage> messages) async {
    try {
      for (final message in messages) {
        if (message.role == MessageRole.error) {
          continue; // Skip error messages
        }

        // Check if message already exists
        final existingMessage = await _chatMessageDao.findByMessageId(message.messageId);
        if (existingMessage != null) {
          continue; // Skip duplicate messages
        }

        // Use ChatMessage's built-in toDb method to convert to DbChatMessage
        final dbMessage = message.toDb(chatId);

        // Convert DbChatMessage to libsql_dart DbChatMessage
        final libsqlDbMessage = DbChatMessage(
          id: dbMessage.id,
          chatId: dbMessage.chatId,
          body: dbMessage.body,
          messageId: dbMessage.messageId,
          parentMessageId: dbMessage.parentMessageId,
          createdAt: dbMessage.createdAt,
          updatedAt: dbMessage.updatedAt,
        );

        await _chatMessageDao.insert(libsqlDbMessage);
      }

      Logger.root.info('Added ${messages.length} messages to chat $chatId');
    } catch (e) {
      Logger.root.severe('Failed to add messages to chat $chatId: $e');
      rethrow;
    }
  }

  @override
  Future<List<ChatMessage>> getChatMessages(int chatId) async {
    try {
      final libsqlDbMessages = await _chatMessageDao.getMessagesForChat(chatId);

      // Convert libsql_dart DbChatMessage to original DbChatMessage then to ChatMessage
      return libsqlDbMessages.map((libsqlDbMessage) {
        // Convert to original DbChatMessage
        final dbMessage = msg.DbChatMessage(
          id: libsqlDbMessage.id,
          chatId: libsqlDbMessage.chatId,
          body: libsqlDbMessage.body,
          messageId: libsqlDbMessage.messageId,
          parentMessageId: libsqlDbMessage.parentMessageId,
          createdAt: libsqlDbMessage.createdAt,
          updatedAt: libsqlDbMessage.updatedAt,
        );

        // Use ChatMessage's built-in fromDb method
        return ChatMessage.fromDb(dbMessage);
      }).toList();
    } catch (e) {
      Logger.root.severe('Failed to get messages for chat $chatId: $e');
      rethrow;
    }
  }

  /// Search chats by content (enhanced functionality)
  Future<List<Chat>> searchChatsByContent(String query, {int limit = 20}) async {
    try {
      return await _chatDao.searchChats(query, limit: limit);
    } catch (e) {
      Logger.root.severe('Failed to search chats by content: $e');
      rethrow;
    }
  }

  /// Get chat statistics
  Future<Map<String, dynamic>> getChatStatistics() async {
    try {
      return await _chatDao.getChatStats();
    } catch (e) {
      Logger.root.severe('Failed to get chat statistics: $e');
      rethrow;
    }
  }

  /// Get message statistics for a specific chat
  Future<Map<String, dynamic>> getMessageStatistics(int chatId) async {
    try {
      return await _chatMessageDao.getMessageStats(chatId);
    } catch (e) {
      Logger.root.severe('Failed to get message statistics for chat $chatId: $e');
      rethrow;
    }
  }

  /// Export chat data for backup/sync
  Future<Map<String, dynamic>> exportChatData({int? chatId}) async {
    try {
      final data = <String, dynamic>{};

      // Export chats
      final chats = chatId != null
          ? [(await _chatDao.findById(chatId))!]
          : await _chatDao.getAllChats();

      data['chats'] = chats.map((chat) => chat.toJson()).toList();

      // Export messages
      final messages = await _chatMessageDao.backupMessages(chatId: chatId);
      data['messages'] = messages;

      data['exportedAt'] = DateTime.now().toIso8601String();
      data['version'] = '1.0';

      return data;
    } catch (e) {
      Logger.root.severe('Failed to export chat data: $e');
      rethrow;
    }
  }

  /// Import chat data from backup/sync
  Future<void> importChatData(Map<String, dynamic> data) async {
    try {
      // Import chats
      if (data['chats'] != null) {
        final chatList = (data['chats'] as List)
            .map((json) => Chat.fromJson(json as Map<String, dynamic>))
            .toList();

        await _chatDao.restoreChats(chatList.map((chat) => chat.toJson()).toList());
      }

      // Import messages
      if (data['messages'] != null) {
        final messageList = (data['messages'] as List)
            .map((json) => DbChatMessage.fromJson(json as Map<String, dynamic>))
            .toList();

        await _chatMessageDao.restoreMessages(messageList.map((msg) => msg.toJson()).toList());
      }

      Logger.root.info('Successfully imported chat data');
    } catch (e) {
      Logger.root.severe('Failed to import chat data: $e');
      rethrow;
    }
  }
}
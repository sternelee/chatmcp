import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart' as path;
import 'package:libsql_dart/libsql_dart.dart';
import 'package:chatmcp/dao/init_db.dart';
import 'package:chatmcp/dao/libsql_database.dart';
import 'package:chatmcp/utils/storage_manager.dart';

/// Helper class to migrate from sqflite to libsql_dart
class DatabaseMigrationHelper {
  static const String _migrationCompleteFlag = 'libsql_migration_complete';

  /// Check if migration has been completed
  static Future<bool> isMigrationComplete() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query('sqlite_master',
        where: "type = 'table' AND name = 'migration_meta'",
        limit: 1,
      );

      if (result.isEmpty) return false;

      final metaResult = await db.query('migration_meta',
        where: 'key = ?',
        whereArgs: [_migrationCompleteFlag],
        limit: 1,
      );

      return metaResult.isNotEmpty && metaResult.first['value'] == 'true';
    } catch (e) {
      Logger.root.warning('Failed to check migration status: $e');
      return false;
    }
  }

  /// Mark migration as complete
  static Future<void> markMigrationComplete() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Create migration meta table if it doesn't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS migration_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          createdAt TEXT NOT NULL
        )
      ''');

      // Mark migration as complete
      await db.insert('migration_meta', {
        'key': _migrationCompleteFlag,
        'value': 'true',
        'createdAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);

      Logger.root.info('Migration marked as complete');
    } catch (e) {
      Logger.root.warning('Failed to mark migration as complete: $e');
    }
  }

  /// Perform migration from sqflite to libsql_dart
  static Future<MigrationResult> migrateToLibSql() async {
    final stopwatch = Stopwatch()..start();

    try {
      Logger.root.info('Starting migration from sqflite to libsql_dart...');

      // Check if migration is already complete
      if (await isMigrationComplete()) {
        Logger.root.info('Migration already completed, skipping...');
        return MigrationResult.success('Migration already completed');
      }

      // Get old database path
      final oldDbPath = await StorageManager.getDatabasePath();
      final oldDbFile = File(oldDbPath);

      if (!await oldDbFile.exists()) {
        throw Exception('Original database file not found at: $oldDbPath');
      }

      // Create new database path for libsql_dart
      final newDbPath = oldDbPath.replaceAll('.db', '_libsql.db');

      // Initialize new database
      final config = DatabaseConfig(
        localPath: newDbPath,
        enableRemoteSync: false, // Will be enabled later
      );

      await LibSqlDatabase.instance.initialize(config);
      final newDb = LibSqlDatabase.instance.client;

      // Get data from old database
      final oldDb = await DatabaseHelper.instance.database;

      // Migrate chat data
      final chatData = await oldDb.query('chat');
      Logger.root.info('Found ${chatData.length} chat records to migrate');

      if (chatData.isNotEmpty) {
        await _migrateChatData(newDb, chatData);
      }

      // Migrate chat_message data
      final messageData = await oldDb.query('chat_message');
      Logger.root.info('Found ${messageData.length} message records to migrate');

      if (messageData.isNotEmpty) {
        await _migrateMessageData(newDb, messageData);
      }

      // Verify migration
      await _verifyMigration(newDb, chatData.length, messageData.length);

      // Mark migration as complete
      await markMigrationComplete();

      stopwatch.stop();
      Logger.root.info('Migration completed successfully in ${stopwatch.elapsedMilliseconds}ms');

      return MigrationResult.success(
        'Successfully migrated ${chatData.length} chats and ${messageData.length} messages',
        duration: stopwatch.elapsed,
      );

    } catch (e, stackTrace) {
      stopwatch.stop();
      Logger.root.severe('Migration failed: $e\n$stackTrace');

      return MigrationResult.failure(
        'Migration failed: $e',
        error: e is Exception ? e : Exception(e.toString()),
        stackTrace: stackTrace,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Migrate chat data
  static Future<void> _migrateChatData(LibsqlClient newDb, List<Map<String, dynamic>> chatData) async {
    await LibSqlDatabase.instance.transaction((txn) async {
      for (final chat in chatData) {
        // Convert data format if needed
        final migratedChat = {
          'id': chat['id'],
          'title': chat['title'] ?? 'Untitled Chat',
          'model': chat['model'], // Keep existing value or null
          'createdAt': chat['createdAt'] ?? DateTime.now().toIso8601String(),
          'updatedAt': chat['updatedAt'] ?? DateTime.now().toIso8601String(),
        };

        // Use the transaction interface properly - libsql_dart transaction uses execute method
        await LibSqlDatabase.instance.client.execute('''
          INSERT INTO chat (id, title, model, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?)
        ''', positional: [
          migratedChat['id'],
          migratedChat['title'],
          migratedChat['model'],
          migratedChat['createdAt'],
          migratedChat['updatedAt'],
        ]);
      }
    });

    Logger.root.info('Successfully migrated ${chatData.length} chat records');
  }

  /// Migrate message data
  static Future<void> _migrateMessageData(LibsqlClient newDb, List<Map<String, dynamic>> messageData) async {
    await LibSqlDatabase.instance.transaction((txn) async {
      for (final message in messageData) {
        // Convert data format if needed
        final migratedMessage = {
          'id': message['id'],
          'chatId': message['chatId'],
          'messageId': message['messageId'] ?? '',
          'parentMessageId': message['parentMessageId'] ?? '',
          'body': message['body'] ?? '',
          'createdAt': message['createdAt'] ?? DateTime.now().toIso8601String(),
          'updatedAt': message['updatedAt'] ?? DateTime.now().toIso8601String(),
        };

        // Use the transaction interface properly - libsql_dart transaction uses execute method
        await LibSqlDatabase.instance.client.execute('''
          INSERT INTO chat_message (id, chatId, messageId, parentMessageId, body, createdAt, updatedAt)
          VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', positional: [
          migratedMessage['id'],
          migratedMessage['chatId'],
          migratedMessage['messageId'],
          migratedMessage['parentMessageId'],
          migratedMessage['body'],
          migratedMessage['createdAt'],
          migratedMessage['updatedAt'],
        ]);
      }
    });

    Logger.root.info('Successfully migrated ${messageData.length} message records');
  }

  /// Verify migration integrity
  static Future<void> _verifyMigration(LibsqlClient newDb, int expectedChats, int expectedMessages) async {
    final chatCount = await newDb.query('SELECT COUNT(*) as count FROM chat');
    final messageCount = await newDb.query('SELECT COUNT(*) as count FROM chat_message');

    final actualChats = chatCount[0]['count'] as int;
    final actualMessages = messageCount[0]['count'] as int;

    if (actualChats != expectedChats) {
      throw Exception('Chat count mismatch: expected $expectedChats, got $actualChats');
    }

    if (actualMessages != expectedMessages) {
      throw Exception('Message count mismatch: expected $expectedMessages, got $actualMessages');
    }

    Logger.root.info('Migration verification passed: $actualChats chats, $actualMessages messages');
  }

  /// Create backup of old database before migration
  static Future<void> createBackup() async {
    try {
      final originalPath = await StorageManager.getDatabasePath();
      final originalFile = File(originalPath);

      if (!await originalFile.exists()) {
        Logger.root.warning('Original database file not found, skipping backup');
        return;
      }

      final backupPath = originalPath.replaceAll('.db', '_backup_${DateTime.now().millisecondsSinceEpoch}.db');
      await originalFile.copy(backupPath);

      Logger.root.info('Database backup created at: $backupPath');
    } catch (e) {
      Logger.root.severe('Failed to create database backup: $e');
      rethrow;
    }
  }

  /// Clean up old database after successful migration
  static Future<void> cleanupOldDatabase() async {
    try {
      final oldPath = await StorageManager.getDatabasePath();
      final oldFile = File(oldPath);

      if (await oldFile.exists()) {
        // Instead of deleting, rename for safety
        final archivePath = oldPath.replaceAll('.db', '_sqflite_old.db');
        await oldFile.rename(archivePath);
        Logger.root.info('Old database archived at: $archivePath');
      }
    } catch (e) {
      Logger.root.warning('Failed to archive old database: $e');
    }
  }

  /// Rollback migration (restore from backup)
  static Future<bool> rollbackMigration() async {
    try {
      Logger.root.info('Attempting to rollback migration...');

      // Find the most recent backup
      final dbDir = path.dirname(await StorageManager.getDatabasePath());
      final dir = Directory(dbDir);

      List<String> backupFiles = [];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('_backup_') && entity.path.endsWith('.db')) {
          backupFiles.add(entity.path);
        }
      }

      if (backupFiles.isEmpty) {
        Logger.root.warning('No backup files found for rollback');
        return false;
      }

      // Sort by timestamp and get the most recent
      backupFiles.sort((a, b) => b.compareTo(a));
      final latestBackup = backupFiles.first;

      final originalPath = await StorageManager.getDatabasePath();
      await File(latestBackup).copy(originalPath);

      Logger.root.info('Migration rollback completed using backup: $latestBackup');
      return true;

    } catch (e) {
      Logger.root.severe('Rollback failed: $e');
      return false;
    }
  }
}

/// Migration result class
class MigrationResult {
  final bool success;
  final String message;
  final Exception? error;
  final StackTrace? stackTrace;
  final Duration duration;

  MigrationResult._({
    required this.success,
    required this.message,
    this.error,
    this.stackTrace,
    required this.duration,
  });

  factory MigrationResult.success(String message, {Duration? duration}) {
    return MigrationResult._(
      success: true,
      message: message,
      duration: duration ?? Duration.zero,
    );
  }

  factory MigrationResult.failure(
    String message, {
    Exception? error,
    StackTrace? stackTrace,
    Duration? duration,
  }) {
    return MigrationResult._(
      success: false,
      message: message,
      error: error,
      stackTrace: stackTrace,
      duration: duration ?? Duration.zero,
    );
  }

  @override
  String toString() {
    return 'MigrationResult{success: $success, message: $message, duration: ${duration.inMilliseconds}ms}';
  }
}
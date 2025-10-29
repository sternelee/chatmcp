import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:chatmcp/dao/libsql_database.dart';
import 'package:chatmcp/dao/database_migration_helper.dart';
import 'package:chatmcp/utils/storage_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced database initialization system using libsql_dart
/// Provides seamless migration from sqflite to libsql_dart with remote sync capabilities
class LibSqlDatabaseHelper {
  static final LibSqlDatabaseHelper instance = LibSqlDatabaseHelper._init();
  static const String _migrationStatusKey = 'libsql_migration_status';
  static const String _databaseVersionKey = 'libsql_database_version';

  LibSqlDatabaseHelper._init();

  bool _isInitialized = false;
  bool _isMigrating = false;
  Completer<void>? _initCompleter;

  /// Initialize database with automatic migration if needed
  Future<void> initialize({bool enableRemoteSync = false}) async {
    if (_isInitialized) return;

    // If initialization is already in progress, wait for it
    if (_initCompleter != null) {
      Logger.root.info('Database initialization already in progress, waiting...');
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      Logger.root.info('Starting libsql_dart database initialization...');

      // Check if we need to migrate from sqflite
      await _checkAndPerformMigration();

      // Initialize libsql_dart database
      await _initializeLibSqlDatabase(enableRemoteSync);

      _isInitialized = true;
      _initCompleter!.complete();

      Logger.root.info('Database initialization completed successfully');
    } catch (e, stackTrace) {
      Logger.root.severe('Database initialization failed: $e\n$stackTrace');
      _initCompleter!.completeError(e, stackTrace);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// Check if migration is needed and perform it
  Future<void> _checkAndPerformMigration() async {
    if (_isMigrating) {
      Logger.root.info('Migration already in progress, skipping...');
      return;
    }

    try {
      // Check if we've already migrated to libsql_dart
      final prefs = await SharedPreferences.getInstance();
      final migrationStatus = prefs.getString(_migrationStatusKey);

      if (migrationStatus == 'completed') {
        Logger.root.info('Already migrated to libsql_dart, skipping migration');
        return;
      }

      // Check if there's an existing sqflite database to migrate from
      final hasOldData = await _hasExistingSqfliteDatabase();

      if (!hasOldData) {
        Logger.root.info('No existing database found, starting fresh with libsql_dart');
        await _markMigrationCompleted();
        return;
      }

      _isMigrating = true;

      // Create backup before migration
      await DatabaseMigrationHelper.createBackup();

      // Perform migration
      final result = await DatabaseMigrationHelper.migrateToLibSql();

      if (result.success) {
        await _markMigrationCompleted();
        Logger.root.info('Migration to libsql_dart completed successfully');
      } else {
        Logger.root.severe('Migration failed: ${result.message}');
        throw Exception('Database migration failed: ${result.message}');
      }

    } catch (e) {
      Logger.root.severe('Migration process failed: $e');
      rethrow;
    } finally {
      _isMigrating = false;
    }
  }

  /// Check if there's an existing sqflite database
  Future<bool> _hasExistingSqfliteDatabase() async {
    try {
      final dbPath = await StorageManager.getDatabasePath();
      final dbFile = File(dbPath);
      return await dbFile.exists();
    } catch (e) {
      Logger.root.warning('Failed to check for existing database: $e');
      return false;
    }
  }

  /// Initialize libsql_dart database
  Future<void> _initializeLibSqlDatabase(bool enableRemoteSync) async {
    final dbPath = await StorageManager.getDatabasePath();

    // Create database path for libsql_dart (different from sqflite path)
    final libsqlDbPath = dbPath.replaceAll('.db', '_libsql.db');

    final config = DatabaseConfig(
      localPath: libsqlDbPath,
      enableRemoteSync: enableRemoteSync,
      // TODO: Add remote configuration when implementing sync
      // remoteUrl: remoteUrl,
      // authToken: authToken,
    );

    await LibSqlDatabase.instance.initialize(config);
  }

  /// Mark migration as completed
  Future<void> _markMigrationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_migrationStatusKey, 'completed');
    await prefs.setInt(_databaseVersionKey, LibSqlDatabase.currentVersion);
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;

  /// Get migration status
  bool get isMigrating => _isMigrating;

  /// Reinitialize database (useful for testing or recovery)
  Future<void> reinitialize({bool forceMigration = false}) async {
    if (forceMigration) {
      // Reset migration status
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_migrationStatusKey);
    }

    _isInitialized = false;
    await initialize();
  }

  /// Enable remote sync for existing database
  Future<void> enableRemoteSync({
    required String remoteUrl,
    String? authToken,
  }) async {
    if (!_isInitialized) {
      throw StateError('Database must be initialized before enabling remote sync');
    }

    Logger.root.info('Enabling remote sync to: $remoteUrl');

    // Create new configuration with remote sync enabled
    final dbPath = await StorageManager.getDatabasePath();
    final libsqlDbPath = dbPath.replaceAll('.db', '_libsql.db');

    final config = DatabaseConfig(
      localPath: libsqlDbPath,
      remoteUrl: remoteUrl,
      authToken: authToken,
      enableRemoteSync: true,
    );

    // Reinitialize with new configuration
    await LibSqlDatabase.instance.close();
    await LibSqlDatabase.instance.initialize(config);

    Logger.root.info('Remote sync enabled successfully');
  }

  /// Disable remote sync
  Future<void> disableRemoteSync() async {
    if (!_isInitialized) {
      throw StateError('Database must be initialized before disabling remote sync');
    }

    Logger.root.info('Disabling remote sync');

    // Create new configuration with remote sync disabled
    final dbPath = await StorageManager.getDatabasePath();
    final libsqlDbPath = dbPath.replaceAll('.db', '_libsql.db');

    final config = DatabaseConfig(
      localPath: libsqlDbPath,
      enableRemoteSync: false,
    );

    // Reinitialize with new configuration
    await LibSqlDatabase.instance.close();
    await LibSqlDatabase.instance.initialize(config);

    Logger.root.info('Remote sync disabled');
  }

  /// Get database information
  Future<Map<String, dynamic>> getDatabaseInfo() async {
    if (!_isInitialized) {
      return {
        'initialized': false,
        'version': 0,
        'remoteSync': false,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final migrationStatus = prefs.getString(_migrationStatusKey);
    final dbVersion = prefs.getInt(_databaseVersionKey) ?? 0;

    return {
      'initialized': _isInitialized,
      'version': dbVersion,
      'migrationStatus': migrationStatus,
      'remoteSync': LibSqlDatabase.instance.isRemoteSyncEnabled,
      'remoteUrl': LibSqlDatabase.instance.remoteUrl,
      'databasePath': await _getDatabasePath(),
    };
  }

  /// Get current database path
  Future<String> _getDatabasePath() async {
    final dbPath = await StorageManager.getDatabasePath();
    return dbPath.replaceAll('.db', '_libsql.db');
  }

  /// Perform database health check
  Future<Map<String, dynamic>> performHealthCheck() async {
    try {
      if (!_isInitialized) {
        return {
          'healthy': false,
          'error': 'Database not initialized',
        };
      }

      final client = LibSqlDatabase.instance.client;

      // Test basic functionality
      await client.query('SELECT 1');

      // Check tables exist
      final tablesResult = await client.query('''
        SELECT name FROM sqlite_master
        WHERE type='table' AND name IN ('chat', 'chat_message')
      ''');

      final tables = tablesResult.map((row) => row['name'] as String).toList();

      // Check row counts
      final chatCount = await client.query('SELECT COUNT(*) as count FROM chat');
      final messageCount = await client.query('SELECT COUNT(*) as count FROM chat_message');

      return {
        'healthy': true,
        'tables': tables,
        'chatCount': chatCount[0]['count'],
        'messageCount': messageCount[0]['count'],
        'remoteSync': LibSqlDatabase.instance.isRemoteSyncEnabled,
      };

    } catch (e) {
      return {
        'healthy': false,
        'error': e.toString(),
      };
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_isInitialized) {
      await LibSqlDatabase.instance.close();
      _isInitialized = false;
      Logger.root.info('Database connection closed');
    }
  }

  /// Reset database completely (for testing/debugging)
  Future<void> reset() async {
    Logger.root.warning('Resetting database - this will delete all data');

    await close();

    // Remove migration status
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationStatusKey);
    await prefs.remove(_databaseVersionKey);

    // Delete database file
    final dbPath = await _getDatabasePath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    Logger.root.info('Database reset completed');
  }
}

/// Convenience function to initialize database
Future<void> initLibSqlDatabase({bool enableRemoteSync = false}) async {
  await LibSqlDatabaseHelper.instance.initialize(enableRemoteSync: enableRemoteSync);
}

/// Convenience function to get database info
Future<Map<String, dynamic>> getLibSqlDatabaseInfo() async {
  return await LibSqlDatabaseHelper.instance.getDatabaseInfo();
}

/// Convenience function to perform health check
Future<Map<String, dynamic>> performLibSqlHealthCheck() async {
  return await LibSqlDatabaseHelper.instance.performHealthCheck();
}
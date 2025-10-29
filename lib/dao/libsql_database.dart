import 'dart:async';
import 'package:libsql_dart/libsql_dart.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/utils/storage_manager.dart';

/// Database configuration for local and remote connections
class DatabaseConfig {
  final String localPath;
  final String? remoteUrl;
  final String? authToken;
  final bool enableRemoteSync;

  const DatabaseConfig({
    required this.localPath,
    this.remoteUrl,
    this.authToken,
    this.enableRemoteSync = false,
  });
}

/// Enhanced database adapter using libsql_dart for local and future remote support
class LibSqlDatabase {
  static final LibSqlDatabase instance = LibSqlDatabase._init();
  static const int currentVersion = 3;
  static const List<String> requiredTables = ['chat', 'chat_message'];

  LibSqlDatabase._init();

  LibsqlClient? _client;
  DatabaseConfig? _config;
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();
  int _lastInsertRowId = 0;

  /// Initialize database with configuration
  Future<void> initialize(DatabaseConfig config) async {
    if (_isInitialized) return;

    _config = config;
    try {
      Logger.root.info('Initializing libsql_dart database...');
      await _initializeDatabase();
      _isInitialized = true;
      _initCompleter.complete();
      Logger.root.info('Database initialized successfully');
    } catch (e, stackTrace) {
      Logger.root.severe('Database initialization failed: $e\n$stackTrace');
      _initCompleter.completeError(e, stackTrace);
      rethrow;
    }
  }

  /// Wait for database initialization
  Future<void> get initialized => _initCompleter.future;

  /// Get database instance (throws if not initialized)
  LibsqlClient get client {
    if (!_isInitialized || _client == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _client!;
  }

  /// Get last insert row ID
  int get lastInsertRowId => _lastInsertRowId;

  /// Initialize the database connection
  Future<void> _initializeDatabase() async {
    final dbPath = _config?.localPath ?? await StorageManager.getDatabasePath();

    Logger.root.info('Opening database at: $dbPath');

    // Create database connection using libsql_dart
    if (_config?.enableRemoteSync == true && _config?.remoteUrl != null) {
      // Remote database connection
      _client = LibsqlClient.remote(_config!.remoteUrl!);
    } else {
      // Local database connection
      _client = LibsqlClient.local(dbPath);
    }

    // Enable foreign keys
    await client.execute('PRAGMA foreign_keys = ON');

    // Initialize schema and run migrations
    await _initializeSchema();
  }

  /// Initialize database schema and run migrations
  Future<void> _initializeSchema() async {
    // Get current user version
    final result = await client.query('PRAGMA user_version');
    final currentVersion = result[0]['user_version'] as int? ?? 0;

    Logger.root.info('Current database version: $currentVersion, target version: ${LibSqlDatabase.currentVersion}');

    // Run migrations
    for (int version = currentVersion + 1; version <= LibSqlDatabase.currentVersion; version++) {
      Logger.root.info('Running migration to version $version');
      await _runMigration(version);
    }

    // Update user version
    await client.execute('PRAGMA user_version = ${LibSqlDatabase.currentVersion}');
  }

  /// Run migration for specific version
  Future<void> _runMigration(int version) async {
    switch (version) {
      case 1:
        await _runMigrationV1();
        break;
      case 2:
        await _runMigrationV2();
        break;
      case 3:
        await _runMigrationV3();
        break;
      default:
        Logger.root.warning('Unknown migration version: $version');
    }
  }

  /// Migration v1 - Create initial tables
  Future<void> _runMigrationV1() async {
    await client.execute('''
      CREATE TABLE IF NOT EXISTS chat (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        model TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await client.execute('''
      CREATE TABLE IF NOT EXISTS chat_message (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chatId INTEGER NOT NULL,
        messageId TEXT NOT NULL,
        parentMessageId TEXT DEFAULT '',
        body TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (chatId) REFERENCES chat(id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for better performance
    await client.execute('CREATE INDEX IF NOT EXISTS idx_chat_created_at ON chat(createdAt)');
    await client.execute('CREATE INDEX IF NOT EXISTS idx_chat_message_chat_id ON chat_message(chatId)');
    await client.execute('CREATE INDEX IF NOT EXISTS idx_chat_message_created_at ON chat_message(createdAt)');
    await client.execute('CREATE INDEX IF NOT EXISTS idx_chat_message_message_id ON chat_message(messageId)');

    Logger.root.info('Migration v1 completed - Created tables and indexes');
  }

  /// Migration v2 - Placeholder for future changes
  Future<void> _runMigrationV2() async {
    Logger.root.info('Migration v2 completed - No changes required');
  }

  /// Migration v3 - Fix model column (same as original sqflite migration)
  Future<void> _runMigrationV3() async {
    Logger.root.info('Running migration v3 - Fixing model column schema');

    // Create backup table
    await client.execute('''
      CREATE TABLE IF NOT EXISTS chat_backup (
        id INTEGER PRIMARY KEY,
        title TEXT,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    // Backup existing data
    await client.execute('''
      INSERT OR IGNORE INTO chat_backup (id, title, createdAt, updatedAt)
      SELECT id, title, createdAt, updatedAt
      FROM chat
      WHERE id IS NOT NULL
    ''');

    // Drop existing table
    await client.execute('DROP TABLE IF EXISTS chat');

    // Create new table with correct schema
    await client.execute('''
      CREATE TABLE chat (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        model TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // Restore data with model as NULL
    await client.execute('''
      INSERT INTO chat (id, title, model, createdAt, updatedAt)
      SELECT id, title, NULL, createdAt, updatedAt
      FROM chat_backup
    ''');

    // Clean up backup table
    await client.execute('DROP TABLE IF EXISTS chat_backup');

    // Recreate indexes
    await client.execute('CREATE INDEX IF NOT EXISTS idx_chat_created_at ON chat(createdAt)');

    Logger.root.info('Migration v3 completed successfully');
  }

  /// Execute a transaction
  Future<T> transaction<T>(Future<T> Function(Object tx) action) async {
    final tx = await client.transaction();
    try {
      final result = await action(tx);
      await tx.commit();
      return result;
    } catch (e) {
      await tx.rollback();
      rethrow;
    }
  }

  /// Execute raw SQL query
  Future<List<Map<String, dynamic>>> select(String sql, [List<Object?>? parameters]) async {
    final result = await client.query(sql, positional: parameters);
    // libsql_dart returns List<Map<String, dynamic>> directly
    return result;
  }

  /// Execute raw SQL command (INSERT, UPDATE, DELETE)
  Future<void> execute(String sql, [List<Object?>? parameters]) async {
    await client.execute(sql, positional: parameters);
  }

  /// Execute INSERT and return last insert row ID
  Future<int> insert(String sql, [List<Object?>? parameters]) async {
    await client.execute(sql, positional: parameters);
    // Get last insert row ID
    final result = await client.query('SELECT last_insert_rowid()');
    _lastInsertRowId = result[0]['last_insert_rowid()'] as int;
    return _lastInsertRowId;
  }

  /// Batch execute multiple statements
  Future<void> batch(List<String> statements, [List<List<Object?>>? parametersList]) async {
    for (int i = 0; i < statements.length; i++) {
      final parameters = parametersList != null && i < parametersList.length
          ? parametersList[i]
          : null;
      await client.execute(statements[i], positional: parameters);
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_client != null) {
      // libsql_dart doesn't seem to have a close method
      // Just clear the reference
      _client = null;
      _isInitialized = false;
      Logger.root.info('Database connection closed');
    }
  }

  /// Check if remote sync is enabled
  bool get isRemoteSyncEnabled => _config?.enableRemoteSync ?? false;

  /// Get remote URL if configured
  String? get remoteUrl => _config?.remoteUrl;

  /// Initialize remote sync connection (placeholder for future implementation)
  Future<void> initializeRemoteSync() async {
    if (!isRemoteSyncEnabled || remoteUrl == null) {
      throw StateError('Remote sync is not enabled or configured');
    }

    // TODO: Implement remote sync initialization
    Logger.root.info('Remote sync initialization not yet implemented');
  }

  /// Sync to remote (placeholder for future implementation)
  Future<void> syncToRemote() async {
    if (!isRemoteSyncEnabled) {
      Logger.root.info('Remote sync is disabled');
      return;
    }

    // TODO: Implement remote sync functionality
    Logger.root.info('Remote sync functionality not yet implemented');
  }
}
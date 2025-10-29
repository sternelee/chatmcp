import 'package:logging/logging.dart';
import 'package:chatmcp/dao/libsql_init_db.dart';
import 'package:chatmcp/dao/database_migration_helper.dart';
import 'package:chatmcp/repository/chat_repository_provider.dart';
import 'package:chatmcp/dao/libsql_database.dart';

/// Service to manage database migration and provide status information
class DatabaseMigrationService {
  static final DatabaseMigrationService _instance = DatabaseMigrationService._internal();
  factory DatabaseMigrationService() => _instance;
  DatabaseMigrationService._internal();

  /// Get current database status
  Future<DatabaseStatus> getDatabaseStatus() async {
    try {
      // Check if using libsql_dart
      final isUsingLibSql = ChatRepositoryProvider.isUsingLibSql;

      // Get database info
      final dbInfo = await getLibSqlDatabaseInfo();

      // Get health check
      final healthCheck = await performLibSqlHealthCheck();

      return DatabaseStatus(
        isUsingLibSql: isUsingLibSql,
        isInitialized: dbInfo['initialized'] ?? false,
        databaseVersion: dbInfo['version'] ?? 0,
        migrationStatus: dbInfo['migrationStatus'],
        remoteSyncEnabled: dbInfo['remoteSync'] ?? false,
        remoteUrl: dbInfo['remoteUrl'],
        isHealthy: healthCheck['healthy'] ?? false,
        chatCount: healthCheck['chatCount'] ?? 0,
        messageCount: healthCheck['messageCount'] ?? 0,
        lastError: healthCheck['error'],
        databasePath: dbInfo['databasePath'],
      );
    } catch (e) {
      Logger.root.severe('Failed to get database status: $e');
      return DatabaseStatus(
        isUsingLibSql: false,
        isInitialized: false,
        isHealthy: false,
        lastError: e.toString(),
      );
    }
  }

  /// Force migration to libsql_dart
  Future<MigrationResult> forceMigrationToLibSql() async {
    try {
      Logger.root.info('Starting forced migration to libsql_dart...');

      // Initialize libsql_dart database
      await LibSqlDatabaseHelper.instance.initialize(enableRemoteSync: false);

      // Enable libsql_dart mode in repository
      ChatRepositoryProvider.enableLibSqlMode();

      Logger.root.info('Successfully migrated to libsql_dart');
      return MigrationResult.success('Successfully migrated to libsql_dart');
    } catch (e) {
      Logger.root.severe('Failed to migrate to libsql_dart: $e');
      return MigrationResult.failure('Failed to migrate to libsql_dart: $e');
    }
  }

  /// Enable remote sync
  Future<MigrationResult> enableRemoteSync(String remoteUrl, {String? authToken}) async {
    try {
      Logger.root.info('Enabling remote sync to: $remoteUrl');

      // Configure remote sync in database
      await LibSqlDatabaseHelper.instance.enableRemoteSync(
        remoteUrl: remoteUrl,
        authToken: authToken,
      );

      Logger.root.info('Remote sync enabled successfully');
      return MigrationResult.success('Remote sync enabled successfully');
    } catch (e) {
      Logger.root.severe('Failed to enable remote sync: $e');
      return MigrationResult.failure('Failed to enable remote sync: $e');
    }
  }

  /// Disable remote sync
  Future<MigrationResult> disableRemoteSync() async {
    try {
      Logger.root.info('Disabling remote sync...');

      await LibSqlDatabaseHelper.instance.disableRemoteSync();

      Logger.root.info('Remote sync disabled successfully');
      return MigrationResult.success('Remote sync disabled successfully');
    } catch (e) {
      Logger.root.severe('Failed to disable remote sync: $e');
      return MigrationResult.failure('Failed to disable remote sync: $e');
    }
  }

  /// Switch back to legacy sqflite mode
  Future<MigrationResult> switchToLegacyMode() async {
    try {
      Logger.root.info('Switching to legacy sqflite mode...');

      ChatRepositoryProvider.enableLegacyMode();

      Logger.root.info('Successfully switched to legacy mode');
      return MigrationResult.success('Successfully switched to legacy mode');
    } catch (e) {
      Logger.root.severe('Failed to switch to legacy mode: $e');
      return MigrationResult.failure('Failed to switch to legacy mode: $e');
    }
  }

  /// Reset database (for testing/debugging)
  Future<MigrationResult> resetDatabase() async {
    try {
      Logger.root.warning('Resetting database...');

      await LibSqlDatabaseHelper.instance.reset();
      ChatRepositoryProvider.reset();

      Logger.root.info('Database reset successfully');
      return MigrationResult.success('Database reset successfully');
    } catch (e) {
      Logger.root.severe('Failed to reset database: $e');
      return MigrationResult.failure('Failed to reset database: $e');
    }
  }

  /// Get migration history
  Future<List<MigrationEvent>> getMigrationHistory() async {
    // This could be extended to store actual migration history
    final events = <MigrationEvent>[];

    try {
      final status = await getDatabaseStatus();

      events.add(MigrationEvent(
        timestamp: DateTime.now(),
        type: MigrationType.statusCheck,
        description: 'Database status checked',
        success: status.isHealthy,
        details: 'Using ${status.isUsingLibSql ? "libsql_dart" : "sqflite"} with ${status.chatCount} chats',
      ));

      if (status.isUsingLibSql && status.migrationStatus != null) {
        events.add(MigrationEvent(
          timestamp: DateTime.now(),
          type: MigrationType.migration,
          description: 'libsql_dart migration',
          success: true,
          details: 'Status: ${status.migrationStatus}',
        ));
      }
    } catch (e) {
      events.add(MigrationEvent(
        timestamp: DateTime.now(),
        type: MigrationType.error,
        description: 'Failed to get migration history',
        success: false,
        details: e.toString(),
      ));
    }

    return events;
  }
}

/// Database status information
class DatabaseStatus {
  final bool isUsingLibSql;
  final bool isInitialized;
  final int databaseVersion;
  final String? migrationStatus;
  final bool remoteSyncEnabled;
  final String? remoteUrl;
  final bool isHealthy;
  final int chatCount;
  final int messageCount;
  final String? lastError;
  final String? databasePath;

  DatabaseStatus({
    required this.isUsingLibSql,
    required this.isInitialized,
    required this.databaseVersion,
    this.migrationStatus,
    required this.remoteSyncEnabled,
    this.remoteUrl,
    required this.isHealthy,
    required this.chatCount,
    required this.messageCount,
    this.lastError,
    this.databasePath,
  });

  @override
  String toString() {
    return 'DatabaseStatus('
        'isUsingLibSql: $isUsingLibSql, '
        'isInitialized: $isInitialized, '
        'databaseVersion: $databaseVersion, '
        'remoteSyncEnabled: $remoteSyncEnabled, '
        'isHealthy: $isHealthy, '
        'chatCount: $chatCount, '
        'messageCount: $messageCount'
        ')';
  }
}

/// Migration event for tracking history
class MigrationEvent {
  final DateTime timestamp;
  final MigrationType type;
  final String description;
  final bool success;
  final String details;

  MigrationEvent({
    required this.timestamp,
    required this.type,
    required this.description,
    required this.success,
    required this.details,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'description': description,
      'success': success,
      'details': details,
    };
  }
}

/// Migration types
enum MigrationType {
  migration,
  statusCheck,
  error,
  configuration,
}

/// Migration result
class MigrationResult {
  final bool success;
  final String message;
  final String? error;

  MigrationResult({required this.success, required this.message, this.error});

  factory MigrationResult.success(String message) {
    return MigrationResult(success: true, message: message);
  }

  factory MigrationResult.failure(String message, {String? error}) {
    return MigrationResult(success: false, message: message, error: error);
  }
}
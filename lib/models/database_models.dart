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
    this.databaseVersion = 0,
    this.migrationStatus,
    this.remoteSyncEnabled = false,
    this.remoteUrl,
    this.isHealthy = false,
    this.chatCount = 0,
    this.messageCount = 0,
    this.lastError,
    this.databasePath,
  });

  @override
  String toString() {
    return 'DatabaseStatus('
        'isUsingLibSql: $isUsingLibSql, '
        'isInitialized: $isInitialized, '
        'isHealthy: $isHealthy, '
        'chatCount: $chatCount, '
        'messageCount: $messageCount, '
        'lastError: $lastError'
        ')';
  }
}

/// Migration result information
class MigrationResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? details;
  final String? error;

  MigrationResult({
    required this.success,
    this.message,
    this.details,
    this.error,
  });

  factory MigrationResult.success({String? message, Map<String, dynamic>? details}) {
    return MigrationResult(
      success: true,
      message: message,
      details: details,
    );
  }

  factory MigrationResult.failure(String error, {String? message, Map<String, dynamic>? details}) {
    return MigrationResult(
      success: false,
      error: error,
      message: message,
      details: details,
    );
  }

  @override
  String toString() {
    return 'MigrationResult(success: $success, message: $message, error: $error)';
  }
}

/// Database health check result
class DatabaseHealthCheck {
  final bool healthy;
  final String? error;
  final Map<String, dynamic> metrics;
  final DateTime timestamp;

  DatabaseHealthCheck({
    required this.healthy,
    this.error,
    this.metrics = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory DatabaseHealthCheck.healthy({Map<String, dynamic>? metrics}) {
    return DatabaseHealthCheck(
      healthy: true,
      metrics: metrics ?? {},
    );
  }

  factory DatabaseHealthCheck.unhealthy(String error, {Map<String, dynamic>? metrics}) {
    return DatabaseHealthCheck(
      healthy: false,
      error: error,
      metrics: metrics ?? {},
    );
  }

  @override
  String toString() {
    return 'DatabaseHealthCheck(healthy: $healthy, error: $error, timestamp: $timestamp)';
  }
}

/// Database connection information
class DatabaseConnectionInfo {
  final String type; // 'local', 'remote', 'memory'
  final String? path;
  final String? url;
  final bool connected;
  final String? error;
  final DateTime? lastConnected;
  final Map<String, dynamic> statistics;

  DatabaseConnectionInfo({
    required this.type,
    this.path,
    this.url,
    this.connected = false,
    this.error,
    this.lastConnected,
    this.statistics = const {},
  });

  factory DatabaseConnectionInfo.local(String path, {bool connected = false, String? error}) {
    return DatabaseConnectionInfo(
      type: 'local',
      path: path,
      connected: connected,
      error: error,
      lastConnected: connected ? DateTime.now() : null,
    );
  }

  factory DatabaseConnectionInfo.remote(String url, {bool connected = false, String? error}) {
    return DatabaseConnectionInfo(
      type: 'remote',
      url: url,
      connected: connected,
      error: error,
      lastConnected: connected ? DateTime.now() : null,
    );
  }

  factory DatabaseConnectionInfo.memory({bool connected = false, String? error}) {
    return DatabaseConnectionInfo(
      type: 'memory',
      connected: connected,
      error: error,
      lastConnected: connected ? DateTime.now() : null,
    );
  }

  @override
  String toString() {
    return 'DatabaseConnectionInfo(type: $type, connected: $connected, path: $path, url: $url, error: $error)';
  }
}

/// Database backup information
class DatabaseBackup {
  final String id;
  final String name;
  final String path;
  final int size;
  final DateTime createdAt;
  final String type; // 'manual', 'auto'
  final Map<String, dynamic>? metadata;

  DatabaseBackup({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.createdAt,
    this.type = 'manual',
    this.metadata,
  });

  factory DatabaseBackup.fromJson(Map<String, dynamic> json) {
    return DatabaseBackup(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      type: json['type'] as String? ?? 'manual',
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'size': size,
      'created_at': createdAt.toIso8601String(),
      'type': type,
      if (metadata != null) 'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'DatabaseBackup(id: $id, name: $name, size: $size, createdAt: $createdAt)';
  }
}

/// Database migration task
class MigrationTask {
  final String id;
  final String type;
  final String status; // 'pending', 'running', 'completed', 'failed'
  final String? description;
  final Map<String, dynamic>? details;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? error;

  MigrationTask({
    required this.id,
    required this.type,
    required this.status,
    this.description,
    this.details,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.error,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MigrationTask.fromJson(Map<String, dynamic> json) {
    return MigrationTask(
      id: json['id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      description: json['description'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'status': status,
      if (description != null) 'description': description,
      if (details != null) 'details': details,
      'created_at': createdAt.toIso8601String(),
      if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (error != null) 'error': error,
    };
  }

  /// Get task duration
  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  /// Check if task is running
  bool get isRunning => status == 'running';

  /// Check if task is completed
  bool get isCompleted => status == 'completed';

  /// Check if task failed
  bool get isFailed => status == 'failed';

  @override
  String toString() {
    return 'MigrationTask(id: $id, type: $type, status: $status, duration: $duration)';
  }
}

/// Database synchronization status
class DatabaseSyncStatus {
  final bool enabled;
  final String? remoteUrl;
  final DateTime? lastSync;
  final DateTime? nextSync;
  final bool syncing;
  final int pendingChanges;
  final String? error;
  final Map<String, dynamic> statistics;

  DatabaseSyncStatus({
    this.enabled = false,
    this.remoteUrl,
    this.lastSync,
    this.nextSync,
    this.syncing = false,
    this.pendingChanges = 0,
    this.error,
    this.statistics = const {},
  });

  factory DatabaseSyncStatus.fromJson(Map<String, dynamic> json) {
    return DatabaseSyncStatus(
      enabled: json['enabled'] as bool? ?? false,
      remoteUrl: json['remoteUrl'] as String?,
      lastSync: json['lastSync'] != null
          ? DateTime.parse(json['lastSync'] as String)
          : null,
      nextSync: json['nextSync'] != null
          ? DateTime.parse(json['nextSync'] as String)
          : null,
      syncing: json['syncing'] as bool? ?? false,
      pendingChanges: json['pendingChanges'] as int? ?? 0,
      error: json['error'] as String?,
      statistics: json['statistics'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      if (remoteUrl != null) 'remoteUrl': remoteUrl,
      if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
      if (nextSync != null) 'nextSync': nextSync!.toIso8601String(),
      'syncing': syncing,
      'pendingChanges': pendingChanges,
      if (error != null) 'error': error,
      'statistics': statistics,
    };
  }

  @override
  String toString() {
    return 'DatabaseSyncStatus(enabled: $enabled, syncing: $syncing, pendingChanges: $pendingChanges)';
  }
}
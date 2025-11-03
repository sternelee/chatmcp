import 'package:chatmcp/repository/chat_repository.dart';
import 'package:chatmcp/repository/local_chat_repository.dart';
import 'package:chatmcp/repository/remote_chat_repository.dart';
import 'package:chatmcp/repository/libsql_chat_repository.dart';

enum RepositoryType { local, remote, libsql }

class ChatRepositoryFactory {
  static ChatRepository create(RepositoryType type, {String? baseUrl, String? apiKey}) {
    switch (type) {
      case RepositoryType.local:
        return LocalChatRepository();
      case RepositoryType.remote:
        if (baseUrl == null || apiKey == null) {
          throw ArgumentError('Remote repository requires baseUrl and apiKey');
        }
        return RemoteChatRepository(baseUrl: baseUrl, apiKey: apiKey);
      case RepositoryType.libsql:
        return LibSqlChatRepository();
    }
  }
}

class ChatRepositoryProvider {
  static ChatRepository? _instance;
  static RepositoryType _currentType = RepositoryType.local; // Default to local (sqflite) for now

  static ChatRepository get instance {
    return _instance ??= ChatRepositoryFactory.create(_currentType);
  }

  static void configure(RepositoryType type, {String? baseUrl, String? apiKey}) {
    _currentType = type;
    _instance = ChatRepositoryFactory.create(type, baseUrl: baseUrl, apiKey: apiKey);
  }

  /// Enable libsql_dart mode (recommended)
  static void enableLibSqlMode() {
    configure(RepositoryType.libsql);
  }

  /// Enable legacy sqflite mode (for fallback)
  static void enableLegacyMode() {
    configure(RepositoryType.local);
  }

  /// Configure remote repository
  static void configureRemote(String baseUrl, String apiKey) {
    configure(RepositoryType.remote, baseUrl: baseUrl, apiKey: apiKey);
  }

  static void reset() {
    _instance = null;
    _currentType = RepositoryType.local; // Reset to local (sqflite) for now
  }

  /// Get current repository type
  static RepositoryType get currentType => _currentType;

  /// Check if using libsql_dart
  static bool get isUsingLibSql => _currentType == RepositoryType.libsql;
}

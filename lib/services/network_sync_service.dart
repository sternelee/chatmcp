import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/dao/init_db.dart';
import 'package:chatmcp/dao/libsql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:chatmcp/utils/platform.dart';
import 'package:chatmcp/repository/libsql_chat_repository.dart';

class NetworkSyncService {
  static final NetworkSyncService _instance = NetworkSyncService._internal();
  factory NetworkSyncService() => _instance;
  NetworkSyncService._internal();

  HttpServer? _server;
  int _port = 8080;
  String? _ipAddress;
  bool _isServerRunning = false;

  // Server state callback
  Function(bool isRunning, String? address, int port)? onServerStateChanged;

  // Sync state callback
  Function(String status, {bool isLoading, bool isSuccess, String? error})? onSyncStateChanged;

  bool get isServerRunning => _isServerRunning;
  String? get serverAddress => _ipAddress;
  int get serverPort => _port;

  /// Start HTTP server
  Future<void> startServer({int port = 8080}) async {
    if (_isServerRunning) return;

    try {
      _port = port;
      _ipAddress = await _getLocalIPAddress();

      final router = Router();

      // Get device info
      router.get('/info', _handleDeviceInfo);

      // Export data
      router.get('/export', _handleExportData);

      // Import data
      router.post('/import', _handleImportData);

      // Health check
      router.get('/health', (Request request) {
        return Response.ok(json.encode({'status': 'ok', 'timestamp': DateTime.now().toIso8601String(), 'device': Platform.operatingSystem}));
      });

      final handler = Pipeline().addMiddleware(corsHeaders()).addMiddleware(logRequests()).addHandler(router.call);

      _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
      _isServerRunning = true;

      Logger.root.info('HTTP sync server started: http://$_ipAddress:$_port');
      onServerStateChanged?.call(true, _ipAddress, _port);
    } catch (e) {
      Logger.root.severe('Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop HTTP server
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      _isServerRunning = false;
      Logger.root.info('HTTP sync server stopped');
      onServerStateChanged?.call(false, null, 0);
    }
  }

  /// Handle device info request
  Future<Response> _handleDeviceInfo(Request request) async {
    try {
      final info = {
        'deviceName': Platform.localHostname,
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'appName': 'ChatMcp',
        'serverUrl': 'http://$_ipAddress:$_port',
        'displayName': '${Platform.localHostname} (${Platform.operatingSystem})',
      };

      return Response.ok(json.encode(info), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: json.encode({'error': e.toString()}));
    }
  }

  /// Handle data export request
  Future<Response> _handleExportData(Request request) async {
    try {
      final data = await _exportAllData();

      return Response.ok(
        json.encode(data),
        headers: {'Content-Type': 'application/json', 'Content-Disposition': 'attachment; filename="chatmcp_backup.json"'},
      );
    } catch (e) {
      Logger.root.severe('Failed to export data: $e');
      return Response.internalServerError(body: json.encode({'error': 'Failed to export data: ${e.toString()}'}));
    }
  }

  /// Handle data import request
  Future<Response> _handleImportData(Request request) async {
    try {
      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;

      await _importAllData(data);

      return Response.ok(json.encode({'success': true, 'message': 'Data imported successfully', 'timestamp': DateTime.now().toIso8601String()}));
    } catch (e) {
      Logger.root.severe('Failed to import data: $e');
      return Response.badRequest(body: json.encode({'error': 'Failed to import data: ${e.toString()}'}));
    }
  }

  /// Sync data from remote server
  Future<void> syncFromRemote(String serverUrl) async {
    try {
      onSyncStateChanged?.call('connectingToServer', isLoading: true);

      final dio = Dio();

      // Check server health first
      final healthResponse = await dio.get('$serverUrl/health');
      if (healthResponse.statusCode != 200) {
        throw Exception('Failed to connect to server');
      }

      Logger.root.info('Connected to remote server: ${healthResponse.data}');
      onSyncStateChanged?.call('downloadingData', isLoading: true);

      // Get remote data
      final exportResponse = await dio.get('$serverUrl/export');
      if (exportResponse.statusCode == 200) {
        onSyncStateChanged?.call('importingData', isLoading: true);
        await _importAllData(exportResponse.data);

        onSyncStateChanged?.call('reinitializingData', isLoading: true);
        // Reinitialize Provider data
        await _reinitializeProviders();

        Logger.root.info('Successfully synced data from remote server');
        onSyncStateChanged?.call('dataSyncSuccess', isSuccess: true);
      } else {
        throw Exception('Failed to get remote data');
      }
    } catch (e) {
      Logger.root.severe('Failed to sync from remote server: $e');
      onSyncStateChanged?.call('syncFailed: $e', error: e.toString());
      rethrow;
    }
  }

  /// Push data to remote server
  Future<void> pushToRemote(String serverUrl) async {
    try {
      onSyncStateChanged?.call('preparingData', isLoading: true);

      final dio = Dio();
      final data = await _exportAllData();

      onSyncStateChanged?.call('uploadingData', isLoading: true);

      final response = await dio.post(
        '$serverUrl/import',
        data: json.encode(data),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        Logger.root.info('Successfully pushed data to remote server');
        onSyncStateChanged?.call('dataPushSuccess', isSuccess: true);
      } else {
        throw Exception('Failed to push data: ${response.data}');
      }
    } catch (e) {
      Logger.root.severe('Failed to push data to remote server: $e');
      onSyncStateChanged?.call('pushFailed: $e', error: e.toString());
      rethrow;
    }
  }

  /// Reinitialize all Provider data
  Future<void> _reinitializeProviders() async {
    try {
      // Reload settings
      await ProviderManager.settingsProvider.loadSettings();

      // Reload chat data
      await ProviderManager.chatProvider.loadChats();

      // Reinitialize MCP servers
      await ProviderManager.mcpServerProvider.init();
      await ProviderManager.mcpServerProvider.loadInMemoryServers();

      Logger.root.info('Provider data reinitialization completed');
    } catch (e) {
      Logger.root.warning('Failed to reinitialize Provider data: $e');
    }
  }

  /// Discover sync servers in local network
  Future<List<String>> discoverServers({int timeoutSeconds = 3}) async {
    final List<String> servers = [];
    final localIP = await _getLocalIPAddress();

    if (localIP == null) return servers;

    // Get network segment (e.g.: 192.168.1.xxx)
    final ipParts = localIP.split('.');
    if (ipParts.length != 4) return servers;

    final networkBase = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}';

    Logger.root.info('Starting to scan local network: $networkBase.xxx');

    // Simplified scan logic, only scan common IPs
    final commonIPs = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110];

    for (int i in commonIPs) {
      final ip = '$networkBase.$i';
      if (ip == localIP) continue; // Skip local IP

      final isActive = await _checkServer(ip, _port, timeoutSeconds);
      if (isActive) {
        servers.add('http://$ip:$_port');
        Logger.root.info('Discovered sync server: $ip:$_port');
      }
    }

    return servers;
  }

  /// Check if specified IP is running sync server
  Future<bool> _checkServer(String ip, int port, int timeoutSeconds) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = Duration(seconds: timeoutSeconds);
      dio.options.receiveTimeout = Duration(seconds: timeoutSeconds);

      final response = await dio.get('http://$ip:$port/health');
      return response.statusCode == 200 && response.data['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  /// Get server device info
  Future<Map<String, dynamic>?> getServerInfo(String serverUrl) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.receiveTimeout = const Duration(seconds: 5);

      final response = await dio.get('$serverUrl/info');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      Logger.root.warning('Failed to get server info: $e');
    }
    return null;
  }

  /// Get local IP address
  Future<String?> _getLocalIPAddress() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      Logger.root.warning('Failed to get IP address: $e');
      return null;
    }
  }

  /// Export all data
  Future<Map<String, dynamic>> _exportAllData() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // Use the new libsql_dart repository for data export
      final repository = LibSqlChatRepository();
      final data = await repository.exportChatData();

      // Export settings
      final settings = <String, dynamic>{};
      for (String key in prefs.getKeys()) {
        final value = prefs.get(key);
        settings[key] = value;
      }

      // Export MCP server config
      Map<String, dynamic>? mcpConfig;
      try {
        final provider = ProviderManager.mcpServerProvider;
        mcpConfig = await provider.loadServersAll();
      } catch (e) {
        Logger.root.warning('Failed to export MCP config: $e');
      }

      return {
        'version': '1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'device': {'name': Platform.localHostname, 'platform': Platform.operatingSystem},
        'chat': data['chats'],
        'chat_message': data['messages'],
        'settings': settings,
        'mcp_config': mcpConfig,
        'repository': 'libsql_dart',
      };
    } catch (e) {
      // Fallback to old sqflite method if libsql_dart fails
      Logger.root.warning('libsql_dart export failed, falling back to sqflite: $e');
      return await _exportSqfliteData(prefs);
    }
  }

  /// Fallback export using old sqflite method
  Future<Map<String, dynamic>> _exportSqfliteData(SharedPreferences prefs) async {
    final db = await DatabaseHelper.instance.database;

    // Export database data
    final chatData = await db.query('chat');
    final messageData = await db.query('chat_message');

    // Export settings
    final settings = <String, dynamic>{};
    for (String key in prefs.getKeys()) {
      final value = prefs.get(key);
      settings[key] = value;
    }

    // Export MCP server config
    Map<String, dynamic>? mcpConfig;
    try {
      final provider = ProviderManager.mcpServerProvider;
      mcpConfig = await provider.loadServersAll();
    } catch (e) {
      Logger.root.warning('Failed to export MCP config: $e');
    }

    return {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'device': {'name': Platform.localHostname, 'platform': Platform.operatingSystem},
      'chat': chatData,
      'chat_message': messageData,
      'settings': settings,
      'mcp_config': mcpConfig,
      'repository': 'sqflite',
    };
  }

  /// Import all data
  Future<void> _importAllData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // Check which repository was used for export
      final repository = data['repository'] as String? ?? 'sqflite';

      if (repository == 'libsql_dart') {
        // Use new libsql_dart repository for import
        final libsqlRepo = LibSqlChatRepository();
        await libsqlRepo.importChatData(data);
        Logger.root.info('Successfully imported data using libsql_dart repository');
      } else {
        // Use old sqflite method for backward compatibility
        await _importSqfliteData(data, prefs);
        Logger.root.info('Successfully imported data using sqflite repository');
      }

      // Import settings (common for both repositories)
      if (data['settings'] != null) {
        final settings = data['settings'] as Map<String, dynamic>;
        for (var entry in settings.entries) {
          if (entry.value is String) {
            await prefs.setString(entry.key, entry.value);
          } else if (entry.value is int) {
            await prefs.setInt(entry.key, entry.value);
          } else if (entry.value is double) {
            await prefs.setDouble(entry.key, entry.value);
          } else if (entry.value is bool) {
            await prefs.setBool(entry.key, entry.value);
          } else if (entry.value is List<String>) {
            await prefs.setStringList(entry.key, entry.value);
          }
        }
      }

      // Import MCP config
      if (data['mcp_config'] != null) {
        Map<String, dynamic>? mcpConfig = data['mcp_config'];

        // 如果当前是移动端，过滤掉stdio格式的MCP server
        if (kIsMobile && mcpConfig != null && mcpConfig['mcpServers'] != null) {
          final servers = mcpConfig['mcpServers'] as Map<String, dynamic>;
          final filteredServers = <String, dynamic>{};

          for (var entry in servers.entries) {
            final serverConfig = entry.value as Map<String, dynamic>;
            final serverType = serverConfig['type'] as String? ?? '';

            // 跳过stdio类型的服务器
            if (serverType != 'stdio') {
              filteredServers[entry.key] = entry.value;
            } else {
              Logger.root.info('Filtered out stdio MCP server: ${entry.key} (mobile platform)');
            }
          }

          mcpConfig['mcpServers'] = filteredServers;
        }

        final provider = ProviderManager.mcpServerProvider;
        await provider.saveServers(mcpConfig!);
      }
    } catch (e) {
      Logger.root.severe('Failed to import data: $e');
      rethrow;
    }
  }

  /// Import data using old sqflite method
  Future<void> _importSqfliteData(Map<String, dynamic> data, SharedPreferences prefs) async {
    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      // Import chat data
      if (data['chat'] != null) {
        for (var chat in data['chat']) {
          try {
            await txn.insert('chat', chat, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (e) {
            // If fields don't match, try to insert only compatible fields
            Logger.root.warning('Failed to insert chat with full schema, trying compatible fields: $e');
            final compatibleChat = <String, dynamic>{
              'id': chat['id'],
              'title': chat['title'],
              'createdAt': chat['createdAt'],
              'updatedAt': chat['updatedAt'],
            };
            // Only add model field if it exists
            if (chat.containsKey('model')) {
              compatibleChat['model'] = chat['model'];
            }
            await txn.insert('chat', compatibleChat, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }

      // Import message data
      if (data['chat_message'] != null) {
        for (var message in data['chat_message']) {
          await txn.insert('chat_message', message, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }
}

/// Connection history model
class SyncServerHistory {
  final String url;
  final String deviceName;
  final String platform;
  final DateTime lastConnected;
  final String displayName;

  SyncServerHistory({required this.url, required this.deviceName, required this.platform, required this.lastConnected, required this.displayName});

  Map<String, dynamic> toJson() {
    return {'url': url, 'deviceName': deviceName, 'platform': platform, 'lastConnected': lastConnected.toIso8601String(), 'displayName': displayName};
  }

  factory SyncServerHistory.fromJson(Map<String, dynamic> json) {
    return SyncServerHistory(
      url: json['url'] ?? '',
      deviceName: json['deviceName'] ?? '',
      platform: json['platform'] ?? '',
      lastConnected: DateTime.tryParse(json['lastConnected'] ?? '') ?? DateTime.now(),
      displayName: json['displayName'] ?? '',
    );
  }
}

/// Connection history manager
class SyncHistoryManager {
  static const String _historyKey = 'sync_server_history';
  static const int _maxHistoryCount = 10;

  /// Save connection history
  static Future<void> saveHistory(SyncServerHistory history) async {
    final prefs = await SharedPreferences.getInstance();
    final histories = await getHistories();

    // Remove old records with same URL
    histories.removeWhere((h) => h.url == history.url);

    // Add new record to the beginning
    histories.insert(0, history);

    // Limit history count
    if (histories.length > _maxHistoryCount) {
      histories.removeRange(_maxHistoryCount, histories.length);
    }

    // Save to SharedPreferences
    final jsonList = histories.map((h) => h.toJson()).toList();
    await prefs.setString(_historyKey, json.encode(jsonList));
  }

  /// Get connection history
  static Future<List<SyncServerHistory>> getHistories() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_historyKey);

    if (historyJson == null) return [];

    try {
      final List<dynamic> jsonList = json.decode(historyJson);
      return jsonList.map((json) => SyncServerHistory.fromJson(json)).toList();
    } catch (e) {
      Logger.root.warning('Failed to parse connection history: $e');
      return [];
    }
  }

  /// Remove connection history
  static Future<void> removeHistory(String url) async {
    final histories = await getHistories();
    histories.removeWhere((h) => h.url == url);

    final prefs = await SharedPreferences.getInstance();
    final jsonList = histories.map((h) => h.toJson()).toList();
    await prefs.setString(_historyKey, json.encode(jsonList));
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}

import 'dart:async';
import 'package:provider/provider.dart';
import 'settings_provider.dart';
import 'mcp_server_provider.dart';
import 'chat_provider.dart';
import 'chat_model_provider.dart';
import 'serve_state_provider.dart';
import 'llm_functionality_provider.dart';
import 'vector_database_provider.dart';
import 'knowledge_base_provider.dart';
import 'package:chatmcp/repository/chat_repository_provider.dart';
import 'package:logging/logging.dart';

class ProviderManager {
  static List<ChangeNotifierProvider> providers = [
    ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
    ChangeNotifierProvider<McpServerProvider>(create: (_) => McpServerProvider()),
    ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
    ChangeNotifierProvider<ChatModelProvider>(create: (_) => ChatModelProvider()),
    ChangeNotifierProvider<ServerStateProvider>(create: (_) => ServerStateProvider()),
    ChangeNotifierProvider<LLMFunctionalityProvider>(create: (_) => LLMFunctionalityProvider()),
    ChangeNotifierProvider<VectorDatabaseProvider>(create: (_) => VectorDatabaseProvider()),
    ChangeNotifierProvider<KnowledgeBaseProvider>(create: (_) => KnowledgeBaseProvider()),
    // Add other Providers here
  ];

  static SettingsProvider? _settingsProvider;

  static SettingsProvider get settingsProvider {
    _settingsProvider ??= SettingsProvider();
    return _settingsProvider!;
  }

  static McpServerProvider? _mcpServerProvider;

  static McpServerProvider get mcpServerProvider {
    _mcpServerProvider ??= McpServerProvider();
    return _mcpServerProvider!;
  }

  static ChatProvider? _chatProvider;

  static ChatProvider get chatProvider {
    _chatProvider ??= ChatProvider();
    return _chatProvider!;
  }

  static ChatModelProvider? _chatModelProvider;

  static ChatModelProvider get chatModelProvider {
    _chatModelProvider ??= ChatModelProvider();
    return _chatModelProvider!;
  }

  static ServerStateProvider? _serverStateProvider;

  static ServerStateProvider get serverStateProvider {
    _serverStateProvider ??= ServerStateProvider();
    return _serverStateProvider!;
  }

  static LLMFunctionalityProvider? _llmFunctionalityProvider;

  static LLMFunctionalityProvider get llmFunctionalityProvider {
    _llmFunctionalityProvider ??= LLMFunctionalityProvider();
    return _llmFunctionalityProvider!;
  }

  static VectorDatabaseProvider? _vectorDatabaseProvider;

  static VectorDatabaseProvider get vectorDatabaseProvider {
    _vectorDatabaseProvider ??= VectorDatabaseProvider();
    return _vectorDatabaseProvider!;
  }

  static KnowledgeBaseProvider? _knowledgeBaseProvider;

  static KnowledgeBaseProvider get knowledgeBaseProvider {
    _knowledgeBaseProvider ??= KnowledgeBaseProvider();
    return _knowledgeBaseProvider!;
  }

  static Future<void> init() async {
    // Temporarily use legacy mode to avoid libsql_dart connection issues
    // Initialize libsql_dart repository by default
    // ChatRepositoryProvider.enableLibSqlMode();
    // Logger.root.info('Initialized libsql_dart repository');

    // Temporarily disable vector database and knowledge base as they depend on libsql_dart
    // Initialize vector database
    // await VectorDatabaseProvider().initialize();

    // Initialize knowledge base
    // await KnowledgeBaseProvider().initialize();

    await SettingsProvider().loadSettings();
    await ChatProvider().loadChats();
    await McpServerProvider().init();
    await McpServerProvider().loadInMemoryServers();
  }
}

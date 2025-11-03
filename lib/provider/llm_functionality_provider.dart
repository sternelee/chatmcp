import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Provider for LLM functionality management
class LLMFunctionalityProvider extends ChangeNotifier {
  static final LLMFunctionalityProvider _instance = LLMFunctionalityProvider._internal();
  factory LLMFunctionalityProvider() => _instance;
  LLMFunctionalityProvider._internal();

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  // LLM capabilities
  bool _supportsEmbeddings = false;
  bool _supportsChatCompletion = true;
  bool _supportsStreaming = true;
  bool _supportsFunctionCalling = false;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get supportsEmbeddings => _supportsEmbeddings;
  bool get supportsChatCompletion => _supportsChatCompletion;
  bool get supportsStreaming => _supportsStreaming;
  bool get supportsFunctionCalling => _supportsFunctionCalling;

  /// Initialize the LLM functionality provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      Logger.root.info('Initializing LLM functionality provider...');

      // Detect LLM capabilities based on available models and providers
      await _detectCapabilities();

      _isInitialized = true;
      Logger.root.info('LLM functionality provider initialized successfully');
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to initialize LLM functionality provider: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Detect LLM capabilities from available models
  Future<void> _detectCapabilities() async {
    try {
      // This would typically check the available models and their capabilities
      // For now, we'll set some default values

      // Most modern LLMs support chat completion and streaming
      _supportsChatCompletion = true;
      _supportsStreaming = true;

      // Function calling support depends on the model
      // This could be configured per model in the settings
      _supportsFunctionCalling = true;

      // Embedding support requires specific embedding models
      _supportsEmbeddings = true; // We'll implement this with the vector database

      Logger.root.info('Detected LLM capabilities: '
          'chat=$_supportsChatCompletion, '
          'streaming=$_supportsStreaming, '
          'functionCalling=$_supportsFunctionCalling, '
          'embeddings=$_supportsEmbeddings');
    } catch (e) {
      Logger.root.warning('Failed to detect LLM capabilities: $e');
    }
  }

  /// Update capabilities based on current model
  void updateCapabilitiesForModel(String modelName, String providerId) {
    try {
      // Update capabilities based on the specific model
      // This is a simplified implementation
      switch (providerId.toLowerCase()) {
        case 'openai':
        case 'claude':
          _supportsChatCompletion = true;
          _supportsStreaming = true;
          _supportsFunctionCalling = true;
          _supportsEmbeddings = false; // OpenAI has separate embedding models
          break;
        case 'ollama':
          _supportsChatCompletion = true;
          _supportsStreaming = true;
          _supportsFunctionCalling = modelName.contains('llama') || modelName.contains('mistral');
          _supportsEmbeddings = modelName.contains('embedding') || modelName.contains('nomic');
          break;
        case 'deepseek':
          _supportsChatCompletion = true;
          _supportsStreaming = true;
          _supportsFunctionCalling = true;
          _supportsEmbeddings = false;
          break;
        default:
          // Default capabilities
          _supportsChatCompletion = true;
          _supportsStreaming = true;
          _supportsFunctionCalling = false;
          _supportsEmbeddings = false;
      }

      notifyListeners();
      Logger.root.info('Updated capabilities for model $modelName ($providerId): '
          'chat=$_supportsChatCompletion, '
          'streaming=$_supportsStreaming, '
          'functionCalling=$_supportsFunctionCalling, '
          'embeddings=$_supportsEmbeddings');
    } catch (e) {
      Logger.root.warning('Failed to update capabilities for model: $e');
    }
  }

  /// Check if a specific capability is supported
  bool isCapabilitySupported(String capability) {
    switch (capability.toLowerCase()) {
      case 'chat':
      case 'chat_completion':
        return _supportsChatCompletion;
      case 'streaming':
      case 'stream':
        return _supportsStreaming;
      case 'function_calling':
      case 'functions':
        return _supportsFunctionCalling;
      case 'embeddings':
      case 'embedding':
        return _supportsEmbeddings;
      default:
        return false;
    }
  }

  /// Get all supported capabilities
  List<String> getSupportedCapabilities() {
    final capabilities = <String>[];
    if (_supportsChatCompletion) capabilities.add('chat_completion');
    if (_supportsStreaming) capabilities.add('streaming');
    if (_supportsFunctionCalling) capabilities.add('function_calling');
    if (_supportsEmbeddings) capabilities.add('embeddings');
    return capabilities;
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Dispose resources
  @override
  void dispose() {
    super.dispose();
  }
}
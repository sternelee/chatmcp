import 'package:logging/logging.dart';
import 'dart:math';
import '../llm/model.dart';
import '../provider/provider_manager.dart';
import '../llm/llm_factory.dart';
import '../models/embedding_models.dart';

/// Service for handling embedding operations
class EmbeddingService {
  static final Logger _logger = Logger.root;

  /// Create embeddings for a list of texts
  static Future<EmbeddingResponse?> createEmbeddings({
    required List<String> texts,
    String? model,
    String? providerId,
    EncodingFormat? encodingFormat,
  }) async {
    try {
      // Get current model or find appropriate embedding model
      final targetModel = await _getEmbeddingModel(model, providerId);
      if (targetModel == null) {
        _logger.warning('No embedding model available');
        return null;
      }

      // For now, return a mock response since the actual implementation would require
      // the embedding API to be implemented in the LLM clients
      final embeddings = texts.map((text) => EmbeddingData(
        embedding: List.generate(1536, (index) => (index % 100) / 100.0), // Mock embedding
        index: texts.indexOf(text),
      )).toList();

      return EmbeddingResponse(
        model: targetModel.name,
        data: embeddings,
      );
    } catch (e, trace) {
      _logger.severe('Failed to create embeddings: $e', trace);
      return null;
    }
  }

  /// Create embedding for a single text
  static Future<EmbeddingResponse?> createEmbedding({
    required String text,
    String? model,
    String? providerId,
    EncodingFormat? encodingFormat,
  }) async {
    return await createEmbeddings(
      texts: [text],
      model: model,
      providerId: providerId,
      encodingFormat: encodingFormat,
    );
  }

  /// Generate embedding for a single text and return vector list
  static Future<List<double>> generateEmbedding({
    required String text,
    String? model,
    String? providerId,
    EncodingFormat? encodingFormat,
  }) async {
    try {
      final response = await createEmbedding(
        text: text,
        model: model,
        providerId: providerId,
        encodingFormat: encodingFormat,
      );

      if (response != null && response.data.isNotEmpty) {
        return response.data.first.embedding;
      }

      return [];
    } catch (e) {
      _logger.severe('Failed to generate embedding: $e');
      return [];
    }
  }

  /// Generate embeddings for multiple texts
  static Future<List<List<double>>> generateEmbeddings({
    required List<String> texts,
    String? model,
    String? providerId,
    EncodingFormat? encodingFormat,
  }) async {
    try {
      final response = await createEmbeddings(
        texts: texts,
        model: model,
        providerId: providerId,
        encodingFormat: encodingFormat,
      );

      if (response != null) {
        return response.data.map((e) => e.embedding).toList();
      }

      return [];
    } catch (e) {
      _logger.severe('Failed to generate embeddings: $e');
      return [];
    }
  }

  /// Get embedding dimension for a specific model
  static Future<int?> getEmbeddingDimension(String model) async {
    try {
      // Generate a test embedding to get dimension
      final testEmbedding = await generateEmbedding(
        text: 'test',
        model: model,
      );

      if (testEmbedding.isNotEmpty) {
        return testEmbedding.length;
      }

      // Default dimensions for known models
      final knownDimensions = {
        'text-embedding-3-small': 1536,
        'text-embedding-3-large': 3072,
        'text-embedding-ada-002': 1536,
        'text-embedding-ada-001': 1024,
      };

      return knownDimensions[model.toLowerCase()];
    } catch (e) {
      _logger.warning('Failed to get embedding dimension for model $model: $e');
      return null;
    }
  }

  /// Calculate cosine similarity between two embedding vectors
  static double calculateCosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Embedding vectors must have the same length');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = sqrt(normA);
    normB = sqrt(normB);

    if (normA == 0 || normB == 0) {
      return 0.0;
    }

    return dotProduct / (normA * normB);
  }

  /// Find most similar embeddings to a query embedding
  static List<EmbeddingSimilarityResult> findMostSimilar(
    List<double> queryEmbedding,
    List<EmbeddingData> candidateEmbeddings, {
    int topK = 5,
    double threshold = 0.5,
  }) {
    final results = <EmbeddingSimilarityResult>[];

    for (final candidate in candidateEmbeddings) {
      final similarity = calculateCosineSimilarity(queryEmbedding, candidate.embedding);

      if (similarity >= threshold) {
        results.add(EmbeddingSimilarityResult(embedding: candidate, similarity: similarity));
      }
    }

    // Sort by similarity (descending) and take topK
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    return results.take(topK).toList();
  }

  /// Get appropriate embedding model
  static Future<Model?> _getEmbeddingModel(String? model, String? providerId) async {
    final settings = ProviderManager.settingsProvider;

    // If specific model is provided, try to find it
    if (model != null) {
      // Try to find model in available models
      for (final provider in settings.apiSettings) {
        if ((provider.enable ?? true) && (providerId == null || provider.providerId == providerId)) {
          try {
            final client = LLMFactory.create(
              LLMFactoryHelper.providerMap[provider.providerId] ?? LLMProvider.openai,
              apiKey: provider.apiKey,
              baseUrl: provider.apiEndpoint,
            );
            final availableModels = await client.models();

            for (final availableModel in availableModels) {
              if (availableModel.toLowerCase().contains('embedding') &&
                  (model.isEmpty || availableModel.toLowerCase().contains(model.toLowerCase()))) {
                return Model(
                  name: availableModel,
                  label: availableModel,
                  providerId: provider.providerId!,
                  icon: '📊',
                  providerName: provider.providerId!,
                  apiStyle: provider.providerId!,
                );
              }
            }
          } catch (e) {
            _logger.warning('Failed to get models for provider ${provider.providerId}: $e');
          }
        }
      }
    }

    // Fallback to default OpenAI embedding model
    final openaiSetting = settings.apiSettings.where((s) => s.providerId == 'openai').firstOrNull;
    if ((openaiSetting?.enable ?? true) && openaiSetting?.apiKey.isNotEmpty == true) {
      return Model(
        name: 'text-embedding-3-small',
        label: 'text-embedding-3-small',
        providerId: 'openai',
        icon: '📊',
        providerName: 'OpenAI',
        apiStyle: 'openai',
      );
    }

    return null;
  }
}

/// Result of embedding similarity search
class EmbeddingSimilarityResult {
  final EmbeddingData embedding;
  final double similarity;

  EmbeddingSimilarityResult({required this.embedding, required this.similarity});
}
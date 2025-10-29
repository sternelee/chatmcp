import 'package:logging/logging.dart';
import '../llm/model.dart';
import '../provider/provider_manager.dart';
import '../llm/llm_factory.dart';

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

      // Create LLM client
      final client = LLMFactoryHelper.createFromModel(targetModel);

      // Create embedding request
      final request = EmbeddingRequest(
        model: targetModel.name,
        inputs: texts,
        encodingFormat: encodingFormat,
      );

      // Generate embeddings
      final response = await client.createEmbedding(request);

      _logger.info('Successfully created ${response.data.length} embeddings using model: ${targetModel.name}');
      return response;
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

    normA = normA.sqrt();
    normB = normB.sqrt();

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
        results.add(EmbeddingSimilarityResult(
          embedding: candidate,
          similarity: similarity,
        ));
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
        if ((provider.enable ?? true) &&
            (providerId == null || provider.providerId == providerId)) {
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

  EmbeddingSimilarityResult({
    required this.embedding,
    required this.similarity,
  });
}

extension on double {
  double sqrt() => this < 0 ? 0.0 : this;
}
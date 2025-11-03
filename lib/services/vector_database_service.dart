import 'dart:async';
import 'package:logging/logging.dart';
import '../services/embedding_service.dart';
import '../dao/vector_database.dart';
import '../dao/vector_collection_dao.dart';
import '../dao/vector_embedding_dao.dart';

/// High-level service for managing vector database operations
class VectorDatabaseService {
  static final VectorDatabaseService _instance = VectorDatabaseService._internal();
  factory VectorDatabaseService() => _instance;
  VectorDatabaseService._internal();

  static final Logger _logger = Logger.root;
  final VectorCollectionDao _collectionDao = VectorCollectionDao();
  final VectorEmbeddingDao _embeddingDao = VectorEmbeddingDao();

  /// Initialize vector database
  static Future<void> initialize() async {
    try {
      await VectorDatabaseSchema.initializeDatabase();
      _logger.info('Vector database service initialized successfully');
    } catch (e, trace) {
      _logger.severe('Failed to initialize vector database: $e', trace);
      rethrow;
    }
  }

  /// Create a new vector collection
  Future<VectorCollection?> createCollection({
    required String name,
    String? description,
    required String modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Check if collection already exists
      final existingCollection = await _collectionDao.getCollectionByName(name);
      if (existingCollection != null) {
        _logger.warning('Collection "$name" already exists');
        return existingCollection;
      }

      // Get embedding dimension by testing the model
      final dimension = await _getEmbeddingDimension(modelName);
      if (dimension == null) {
        _logger.severe('Could not determine embedding dimension for model: $modelName');
        return null;
      }

      final collection = await _collectionDao.createCollection(
        name: name,
        description: description,
        dimension: dimension,
        modelName: modelName,
        metadata: metadata,
      );

      if (collection != null) {
        _logger.info('Created vector collection: ${collection.name} (${collection.dimension}D)');
      }

      return collection;
    } catch (e) {
      _logger.severe('Failed to create collection: $e');
      return null;
    }
  }

  /// Add text embeddings to a collection
  Future<List<VectorEmbedding>?> addTextEmbeddings({
    required String collectionName,
    required List<String> texts,
    String? modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Get collection
      final collection = await _collectionDao.getCollectionByName(collectionName);
      if (collection == null) {
        _logger.severe('Collection "$collectionName" not found');
        return null;
      }

      // Generate embeddings
      final embeddingResponse = await EmbeddingService.createEmbeddings(texts: texts, model: modelName ?? collection.modelName);

      if (embeddingResponse == null || embeddingResponse.data.isEmpty) {
        _logger.severe('Failed to generate embeddings');
        return null;
      }

      // Add embeddings to database
      final embeddings = await _embeddingDao.addEmbeddingsBatch(
        collectionId: collection.id!,
        embeddings: texts.asMap().entries.map((entry) {
          final index = entry.key;
          final text = entry.value;
          return (content: text, embedding: embeddingResponse.data[index].embedding, metadata: metadata);
        }).toList(),
      );

      _logger.info('Added ${embeddings.length} embeddings to collection "$collectionName"');
      return embeddings;
    } catch (e) {
      _logger.severe('Failed to add text embeddings: $e');
      return null;
    }
  }

  /// Add a single text embedding to a collection
  Future<VectorEmbedding?> addTextEmbedding({
    required String collectionName,
    required String text,
    String? modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final embeddings = await addTextEmbeddings(collectionName: collectionName, texts: [text], modelName: modelName, metadata: metadata);

      return embeddings?.isNotEmpty == true ? embeddings!.first : null;
    } catch (e) {
      _logger.severe('Failed to add text embedding: $e');
      return null;
    }
  }

  /// Search for similar texts using vector similarity
  Future<List<VectorSearchResult>> searchSimilarTexts({
    required String collectionName,
    required String queryText,
    int limit = 10,
    double threshold = 0.0,
    String? modelName,
  }) async {
    try {
      // Get collection
      final collection = await _collectionDao.getCollectionByName(collectionName);
      if (collection == null) {
        _logger.severe('Collection "$collectionName" not found');
        return [];
      }

      // Generate embedding for query text
      final embeddingResponse = await EmbeddingService.createEmbedding(text: queryText, model: modelName ?? collection.modelName);

      if (embeddingResponse == null || embeddingResponse.data.isEmpty) {
        _logger.severe('Failed to generate embedding for query text');
        return [];
      }

      // Search for similar embeddings
      final results = await _embeddingDao.searchSimilar(
        collectionId: collection.id!,
        queryEmbedding: embeddingResponse.data.first.embedding,
        limit: limit,
        threshold: threshold,
      );

      _logger.info('Found ${results.length} similar texts for query: "$queryText"');
      return results;
    } catch (e) {
      _logger.severe('Failed to search similar texts: $e');
      return [];
    }
  }

  /// Advanced vector search with filters
  Future<List<VectorSearchResult>> advancedSearch({
    required String collectionName,
    required String queryText,
    int limit = 10,
    double threshold = 0.0,
    String? contentFilter,
    Map<String, dynamic>? metadataFilter,
    String? modelName,
  }) async {
    try {
      // Get collection
      final collection = await _collectionDao.getCollectionByName(collectionName);
      if (collection == null) {
        _logger.severe('Collection "$collectionName" not found');
        return [];
      }

      // Generate embedding for query text
      final embeddingResponse = await EmbeddingService.createEmbedding(text: queryText, model: modelName ?? collection.modelName);

      if (embeddingResponse == null || embeddingResponse.data.isEmpty) {
        _logger.severe('Failed to generate embedding for query text');
        return [];
      }

      // Create search parameters
      final searchParams = VectorSearchParams(
        collectionId: collection.id!,
        queryEmbedding: embeddingResponse.data.first.embedding,
        limit: limit,
        threshold: threshold,
        contentFilter: contentFilter,
        metadataFilter: metadataFilter,
      );

      // Perform advanced search
      final results = await _embeddingDao.advancedSearch(params: searchParams);

      _logger.info('Advanced search found ${results.length} results');
      return results;
    } catch (e) {
      _logger.severe('Failed to perform advanced search: $e');
      return [];
    }
  }

  /// Get all collections
  Future<List<VectorCollection>> getAllCollections() async {
    try {
      return await _collectionDao.getAllCollections();
    } catch (e) {
      _logger.severe('Failed to get all collections: $e');
      return [];
    }
  }

  /// Get collection by name
  Future<VectorCollection?> getCollection(String name) async {
    try {
      return await _collectionDao.getCollectionByName(name);
    } catch (e) {
      _logger.severe('Failed to get collection: $e');
      return null;
    }
  }

  /// Delete collection
  Future<bool> deleteCollection(String name) async {
    try {
      final success = await _collectionDao.deleteCollectionByName(name);
      if (success) {
        _logger.info('Deleted collection: $name');
      }
      return success;
    } catch (e) {
      _logger.severe('Failed to delete collection: $e');
      return false;
    }
  }

  /// Get embeddings from collection
  Future<List<VectorEmbedding>> getEmbeddings({required String collectionName, int? limit, int? offset, String? contentFilter}) async {
    try {
      final collection = await _collectionDao.getCollectionByName(collectionName);
      if (collection == null) {
        _logger.severe('Collection "$collectionName" not found');
        return [];
      }

      return await _embeddingDao.getEmbeddingsByCollection(collectionId: collection.id!, limit: limit, offset: offset, contentFilter: contentFilter);
    } catch (e) {
      _logger.severe('Failed to get embeddings: $e');
      return [];
    }
  }

  /// Get database statistics
  Future<VectorDatabaseStats> getDatabaseStats() async {
    try {
      final collections = await _collectionDao.getAllCollections();
      final totalCollections = collections.length;

      int totalEmbeddings = 0;
      final embeddingsByCollection = <String, int>{};
      final availableModels = <String>{};

      for (final collection in collections) {
        final count = await _embeddingDao.getEmbeddingCount(collection.id!);
        totalEmbeddings += count;
        embeddingsByCollection[collection.name] = count;
        availableModels.add(collection.modelName);
      }

      return VectorDatabaseStats(
        totalCollections: totalCollections,
        totalEmbeddings: totalEmbeddings,
        embeddingsByCollection: embeddingsByCollection,
        availableModels: availableModels.toList(),
      );
    } catch (e) {
      _logger.severe('Failed to get database stats: $e');
      return VectorDatabaseStats(totalCollections: 0, totalEmbeddings: 0, embeddingsByCollection: {}, availableModels: []);
    }
  }

  /// Search embeddings by content (text-based search)
  Future<List<VectorEmbedding>> searchByContent({required String collectionName, required String query, int limit = 10}) async {
    try {
      final collection = await _collectionDao.getCollectionByName(collectionName);
      if (collection == null) {
        _logger.severe('Collection "$collectionName" not found');
        return [];
      }

      return await _embeddingDao.searchByContent(collectionId: collection.id!, query: query, limit: limit);
    } catch (e) {
      _logger.severe('Failed to search by content: $e');
      return [];
    }
  }

  /// Update collection metadata
  Future<bool> updateCollection({required String name, String? description, Map<String, dynamic>? metadata}) async {
    try {
      final collection = await _collectionDao.getCollectionByName(name);
      if (collection == null) {
        _logger.severe('Collection "$name" not found');
        return false;
      }

      final updatedCollection = collection.copyWith(
        description: description ?? collection.description,
        metadata: metadata ?? collection.metadata,
        updatedAt: DateTime.now(),
      );

      return await _collectionDao.updateCollection(updatedCollection);
    } catch (e) {
      _logger.severe('Failed to update collection: $e');
      return false;
    }
  }

  /// Get embedding dimension by testing the model
  Future<int?> _getEmbeddingDimension(String modelName) async {
    try {
      // Use a simple test text to get embedding dimension
      const testText = "test";
      final response = await EmbeddingService.createEmbedding(text: testText, model: modelName);

      return response?.data.first.embedding.length;
    } catch (e) {
      _logger.severe('Failed to get embedding dimension for model $modelName: $e');
      return null;
    }
  }

  /// Check if collection exists
  Future<bool> collectionExists(String name) async {
    try {
      return await _collectionDao.collectionExists(name);
    } catch (e) {
      _logger.severe('Failed to check collection existence: $e');
      return false;
    }
  }

  /// Create or get collection (idempotent operation)
  Future<VectorCollection?> getOrCreateCollection({
    required String name,
    String? description,
    required String modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final existingCollection = await _collectionDao.getCollectionByName(name);
      if (existingCollection != null) {
        return existingCollection;
      }

      return await createCollection(name: name, description: description, modelName: modelName, metadata: metadata);
    } catch (e) {
      _logger.severe('Failed to get or create collection: $e');
      return null;
    }
  }

  /// Delete embedding by ID
  Future<bool> deleteEmbedding(int embeddingId) async {
    try {
      return await _embeddingDao.deleteEmbedding(embeddingId);
    } catch (e) {
      _logger.severe('Failed to delete embedding: $e');
      return false;
    }
  }

  /// Clear all data (for testing purposes)
  Future<bool> clearAllData() async {
    try {
      final collections = await _collectionDao.getAllCollections();

      for (final collection in collections) {
        await _collectionDao.deleteCollection(collection.id!);
      }

      _logger.info('Cleared all vector database data');
      return true;
    } catch (e) {
      _logger.severe('Failed to clear all data: $e');
      return false;
    }
  }
}

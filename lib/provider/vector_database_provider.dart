import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../dao/vector_database.dart';
import '../dao/vector_collection_dao.dart';
import '../dao/vector_embedding_dao.dart';

/// Provider for vector database operations
class VectorDatabaseProvider extends ChangeNotifier {
  static final VectorDatabaseProvider _instance = VectorDatabaseProvider._internal();
  factory VectorDatabaseProvider() => _instance;
  VectorDatabaseProvider._internal();

  final VectorCollectionDao _collectionDao = VectorCollectionDao();
  final VectorEmbeddingDao _embeddingDao = VectorEmbeddingDao();

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  // Collections cache
  List<VectorCollection> _collections = [];
  Map<int, VectorCollection> _collectionMap = {};

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<VectorCollection> get collections => List.unmodifiable(_collections);

  /// Initialize the vector database
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      Logger.root.info('Initializing vector database provider...');

      // Initialize database schema
      await VectorDatabaseSchema.initializeDatabase();

      // Load collections
      await _loadCollections();

      _isInitialized = true;
      Logger.root.info('Vector database provider initialized successfully');
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to initialize vector database provider: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load all collections from database
  Future<void> _loadCollections() async {
    try {
      _collections = await _collectionDao.getAllCollections();
      _collectionMap = {for (var collection in _collections) collection.id!: collection};
    } catch (e) {
      Logger.root.severe('Failed to load collections: $e');
      rethrow;
    }
  }

  /// Refresh collections cache
  Future<void> refreshCollections() async {
    try {
      await _loadCollections();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Create a new vector collection
  Future<VectorCollection?> createCollection({
    required String name,
    String? description,
    required int dimension,
    required String modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final collection = await _collectionDao.createCollection(
        name: name,
        description: description,
        dimension: dimension,
        modelName: modelName,
        metadata: metadata,
      );

      if (collection != null) {
        _collections.insert(0, collection);
        _collectionMap[collection.id!] = collection;
        notifyListeners();
        Logger.root.info('Created vector collection: ${collection.name}');
      }

      return collection;
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to create collection: $e');
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get collection by ID
  VectorCollection? getCollectionById(int id) {
    return _collectionMap[id];
  }

  /// Get collection by name
  VectorCollection? getCollectionByName(String name) {
    try {
      return _collections.firstWhere((c) => c.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Update collection
  Future<bool> updateCollection(VectorCollection collection) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final success = await _collectionDao.updateCollection(collection);

      if (success) {
        final index = _collections.indexWhere((c) => c.id == collection.id);
        if (index != -1) {
          _collections[index] = collection;
          _collectionMap[collection.id!] = collection;
        }
        notifyListeners();
        Logger.root.info('Updated collection: ${collection.name}');
      }

      return success;
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to update collection: $e');
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete collection
  Future<bool> deleteCollection(int collectionId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final success = await _collectionDao.deleteCollection(collectionId);

      if (success) {
        _collections.removeWhere((c) => c.id == collectionId);
        _collectionMap.remove(collectionId);
        notifyListeners();
        Logger.root.info('Deleted collection: $collectionId');
      }

      return success;
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to delete collection: $e');
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add embedding to collection
  Future<VectorEmbedding?> addEmbedding({
    required int collectionId,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final vectorEmbedding = await _embeddingDao.addEmbedding(
        collectionId: collectionId,
        content: content,
        embedding: embedding,
        metadata: metadata,
      );

      if (vectorEmbedding != null) {
        Logger.root.info('Added embedding to collection: $collectionId');
      }

      return vectorEmbedding;
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to add embedding: $e');
      return null;
    }
  }

  /// Add multiple embeddings in batch
  Future<List<VectorEmbedding>> addEmbeddingsBatch({
    required int collectionId,
    required List<({String content, List<double> embedding, Map<String, dynamic>? metadata})> embeddings,
  }) async {
    try {
      final vectorEmbeddings = await _embeddingDao.addEmbeddingsBatch(
        collectionId: collectionId,
        embeddings: embeddings,
      );

      Logger.root.info('Added ${vectorEmbeddings.length} embeddings to collection: $collectionId');
      return vectorEmbeddings;
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to add embeddings batch: $e');
      return [];
    }
  }

  /// Search for similar embeddings
  Future<List<VectorSearchResult>> searchSimilar({
    required int collectionId,
    required List<double> queryEmbedding,
    int limit = 10,
    double threshold = 0.0,
    String? contentFilter,
    Map<String, dynamic>? metadataFilter,
  }) async {
    try {
      return await _embeddingDao.searchSimilar(
        collectionId: collectionId,
        queryEmbedding: queryEmbedding,
        limit: limit,
        threshold: threshold,
        contentFilter: contentFilter,
        metadataFilter: metadataFilter,
      );
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to search similar embeddings: $e');
      return [];
    }
  }

  /// Advanced search with parameters
  Future<List<VectorSearchResult>> advancedSearch(VectorSearchParams params) async {
    try {
      return await _embeddingDao.advancedSearch(params: params);
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to perform advanced search: $e');
      return [];
    }
  }

  /// Get embeddings by collection
  Future<List<VectorEmbedding>> getEmbeddingsByCollection({
    required int collectionId,
    int? limit,
    int? offset,
    String? contentFilter,
  }) async {
    try {
      return await _embeddingDao.getEmbeddingsByCollection(
        collectionId: collectionId,
        limit: limit,
        offset: offset,
        contentFilter: contentFilter,
      );
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to get embeddings by collection: $e');
      return [];
    }
  }

  /// Get embedding count for collection
  Future<int> getEmbeddingCount(int collectionId) async {
    try {
      return await _embeddingDao.getEmbeddingCount(collectionId);
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to get embedding count: $e');
      return 0;
    }
  }

  /// Get collection statistics
  Future<Map<String, dynamic>?> getCollectionStats(int collectionId) async {
    try {
      return await _collectionDao.getCollectionStats(collectionId);
    } catch (e) {
      _error = e.toString();
      Logger.root.severe('Failed to get collection stats: $e');
      return null;
    }
  }

  /// Get database statistics
  Future<VectorDatabaseStats> getDatabaseStats() async {
    try {
      final totalCollections = _collections.length;
      int totalEmbeddings = 0;
      final embeddingsByCollection = <String, int>{};
      final availableModels = <String>{};

      for (final collection in _collections) {
        final count = await getEmbeddingCount(collection.id!);
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
      _error = e.toString();
      Logger.root.severe('Failed to get database stats: $e');
      return VectorDatabaseStats(
        totalCollections: 0,
        totalEmbeddings: 0,
        embeddingsByCollection: {},
        availableModels: [],
      );
    }
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
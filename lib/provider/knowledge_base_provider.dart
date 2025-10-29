import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import '../dao/vector_database.dart';
import '../services/vector_database_service.dart';
import '../services/document_vector_service.dart';

/// Provider for knowledge base management
class KnowledgeBaseProvider extends ChangeNotifier {
  static final Logger _logger = Logger.root;
  final DocumentVectorService _documentService = DocumentVectorService();
  final VectorDatabaseService _vectorService = VectorDatabaseService();

  // State management
  bool _isLoading = false;
  bool _isProcessing = false;
  String? _lastError;

  // Knowledge base data
  List<VectorCollection> _collections = [];
  final List<DocumentInfo> _selectedDocuments = [];
  List<DocumentInfo> _processingDocuments = [];
  Map<String, dynamic> _statistics = {};

  // Configuration
  String _currentCollectionName = '';
  String _currentModelName = 'text-embedding-3-small';
  int _chunkSize = 500;
  int _chunkOverlap = 50;

  // Getters
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get lastError => _lastError;
  List<VectorCollection> get collections => List.unmodifiable(_collections);
  List<DocumentInfo> get selectedDocuments => List.unmodifiable(_selectedDocuments);
  List<DocumentInfo> get processingDocuments => List.unmodifiable(_processingDocuments);
  Map<String, dynamic> get statistics => Map.unmodifiable(_statistics);

  String get currentCollectionName => _currentCollectionName;
  String get currentModelName => _currentModelName;
  int get chunkSize => _chunkSize;
  int get chunkOverlap => _chunkOverlap;

  /// Initialize knowledge base provider
  Future<bool> initialize() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      await refreshCollections();
      await refreshStatistics();
      _logger.info('Knowledge base provider initialized successfully');
      return true;
    } catch (e) {
      final errorMsg = 'Failed to initialize knowledge base: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new knowledge base collection
  Future<VectorCollection?> createKnowledgeBase({
    required String name,
    String? description,
    String? modelName,
  }) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final collection = await _vectorService.createCollection(
        name: name,
        description: description ?? 'Knowledge base: $name',
        modelName: modelName ?? _currentModelName,
        metadata: {
          'type': 'knowledge_base',
          'created_by': 'user',
          'auto_created': false,
        },
      );

      if (collection != null) {
        _currentCollectionName = collection.name;
        await refreshCollections();
        await refreshStatistics();
        _logger.info('Created knowledge base: ${collection.name}');
      }

      return collection;
    } catch (e) {
      final errorMsg = 'Failed to create knowledge base: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import documents to knowledge base
  Future<bool> importDocuments({
    required String collectionName,
    String? modelName,
    int? chunkSize,
    int? chunkOverlap,
  }) async {
    if (_selectedDocuments.isEmpty) {
      _setError('No documents selected for import');
      return false;
    }

    _isProcessing = true;
    _lastError = null;
    notifyListeners();

    try {
      // Create processing config
      final config = DocumentProcessingConfig(
        collectionName: collectionName,
        modelName: modelName ?? _currentModelName,
        chunkSize: chunkSize ?? _chunkSize,
        chunkOverlap: chunkOverlap ?? _chunkOverlap,
        metadata: {
          'import_source': 'knowledge_base_ui',
          'import_timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Process documents
      final processedDocuments = await _documentService.processDocuments(
        documents: _selectedDocuments,
        config: config,
        onProgress: (document) {
          _updateDocumentProgress(document);
        },
      );

      // Update processing documents list
      _processingDocuments = processedDocuments;
      notifyListeners();

      // Check results
      final successCount = processedDocuments
          .where((doc) => doc.status == DocumentProcessingStatus.completed)
          .length;

      final errorCount = processedDocuments
          .where((doc) => doc.status == DocumentProcessingStatus.error)
          .length;

      _logger.info('Document import completed: $successCount successful, $errorCount failed');

      // Refresh data
      await refreshCollections();
      await refreshStatistics();

      // Clear selected documents after successful import
      if (successCount > 0) {
        _selectedDocuments.clear();
        notifyListeners();
      }

      return successCount > 0;
    } catch (e) {
      final errorMsg = 'Failed to import documents: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return false;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Pick documents from file system
  Future<bool> pickDocuments() async {
    try {
      final files = await _documentService.pickDocuments();
      if (files.isEmpty) {
        _logger.info('No documents selected');
        return false;
      }

      final documentInfos = _documentService.createDocumentInfos(files);
      _selectedDocuments.addAll(documentInfos);
      notifyListeners();

      _logger.info('Selected ${files.length} documents for import');
      return true;
    } catch (e) {
      final errorMsg = 'Failed to pick documents: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return false;
    }
  }

  /// Add document to selection
  void addDocument(DocumentInfo document) {
    if (!_selectedDocuments.any((doc) => doc.id == document.id)) {
      _selectedDocuments.add(document);
      notifyListeners();
    }
  }

  /// Remove document from selection
  void removeDocument(String documentId) {
    _selectedDocuments.removeWhere((doc) => doc.id == documentId);
    notifyListeners();
  }

  /// Clear selected documents
  void clearSelectedDocuments() {
    _selectedDocuments.clear();
    notifyListeners();
  }

  /// Delete knowledge base collection
  Future<bool> deleteKnowledgeBase(String collectionName) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final success = await _vectorService.deleteCollection(collectionName);
      if (success) {
        if (_currentCollectionName == collectionName) {
          _currentCollectionName = '';
        }
        await refreshCollections();
        await refreshStatistics();
        _logger.info('Deleted knowledge base: $collectionName');
      }
      return success;
    } catch (e) {
      final errorMsg = 'Failed to delete knowledge base: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search in knowledge base
  Future<List<VectorSearchResult>> searchKnowledgeBase({
    required String collectionName,
    required String queryText,
    int limit = 10,
    double threshold = 0.3,
  }) async {
    try {
      final results = await _vectorService.searchSimilarTexts(
        collectionName: collectionName,
        queryText: queryText,
        limit: limit,
        threshold: threshold,
      );

      _logger.info('Found ${results.length} results in knowledge base: $collectionName');
      return results;
    } catch (e) {
      final errorMsg = 'Failed to search knowledge base: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return [];
    }
  }

  /// Advanced search in knowledge base
  Future<List<VectorSearchResult>> advancedSearchKnowledgeBase({
    required String collectionName,
    required String queryText,
    int limit = 10,
    double threshold = 0.3,
    String? contentFilter,
    Map<String, dynamic>? metadataFilter,
  }) async {
    try {
      final results = await _vectorService.advancedSearch(
        collectionName: collectionName,
        queryText: queryText,
        limit: limit,
        threshold: threshold,
        contentFilter: contentFilter,
        metadataFilter: metadataFilter,
      );

      _logger.info('Advanced search found ${results.length} results in: $collectionName');
      return results;
    } catch (e) {
      final errorMsg = 'Failed to perform advanced search: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return [];
    }
  }

  /// Get documents from collection
  Future<List<VectorEmbedding>> getKnowledgeBaseDocuments({
    required String collectionName,
    int? limit,
    String? contentFilter,
  }) async {
    try {
      return await _vectorService.getEmbeddings(
        collectionName: collectionName,
        limit: limit,
        contentFilter: contentFilter,
      );
    } catch (e) {
      final errorMsg = 'Failed to get knowledge base documents: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return [];
    }
  }

  /// Refresh collections list
  Future<void> refreshCollections() async {
    try {
      _collections = await _vectorService.getAllCollections();
      notifyListeners();
    } catch (e) {
      _logger.severe('Failed to refresh collections: $e');
    }
  }

  /// Refresh statistics
  Future<void> refreshStatistics() async {
    try {
      _statistics = await _documentService.getProcessingStatistics();
      notifyListeners();
    } catch (e) {
      _logger.severe('Failed to refresh statistics: $e');
    }
  }

  /// Update configuration
  void updateConfiguration({
    String? collectionName,
    String? modelName,
    int? chunkSize,
    int? chunkOverlap,
  }) {
    if (collectionName != null) _currentCollectionName = collectionName;
    if (modelName != null) _currentModelName = modelName;
    if (chunkSize != null) _chunkSize = chunkSize;
    if (chunkOverlap != null) _chunkOverlap = chunkOverlap;
    notifyListeners();
  }

  /// Get supported file types
  List<String> getSupportedFileTypes() {
    return _documentService.getSupportedFileTypes();
  }

  /// Check if file type is supported
  bool isFileTypeSupported(String fileName) {
    return _documentService.isFileTypeSupported(fileName);
  }

  /// Get collection statistics
  Future<Map<String, dynamic>?> getCollectionStats(String collectionName) async {
    try {
      final collection = await _vectorService.getCollection(collectionName);
      if (collection == null) return null;

      final count = await _vectorService.getEmbeddings(collectionName: collectionName);
      return {
        'collection': collection,
        'documentCount': count,
        'name': collection.name,
        'description': collection.description,
        'dimension': collection.dimension,
        'modelName': collection.modelName,
        'createdAt': collection.createdAt,
      };
    } catch (e) {
      _logger.severe('Failed to get collection stats: $e');
      return null;
    }
  }

  /// Update collection metadata
  Future<bool> updateCollectionMetadata({
    required String collectionName,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final success = await _vectorService.updateCollection(
        name: collectionName,
        description: description,
        metadata: metadata,
      );

      if (success) {
        await refreshCollections();
        _logger.info('Updated collection metadata: $collectionName');
      }

      return success;
    } catch (e) {
      final errorMsg = 'Failed to update collection metadata: $e';
      _setError(errorMsg);
      _logger.severe(errorMsg);
      return false;
    }
  }

  /// Update document progress during processing
  void _updateDocumentProgress(DocumentInfo document) {
    final index = _processingDocuments.indexWhere((doc) => doc.id == document.id);
    if (index >= 0) {
      _processingDocuments[index] = document;
      notifyListeners();
    } else {
      _processingDocuments.add(document);
      notifyListeners();
    }
  }

  /// Clear error state
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Clear processing results
  void clearProcessingResults() {
    _processingDocuments.clear();
    notifyListeners();
  }

  /// Set current collection
  void setCurrentCollection(String collectionName) {
    _currentCollectionName = collectionName;
    notifyListeners();
  }

  /// Set error state
  void _setError(String error) {
    _lastError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    clearSelectedDocuments();
    clearProcessingResults();
    super.dispose();
  }
}
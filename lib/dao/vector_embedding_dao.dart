import 'dart:convert';
import 'dart:math';
import 'package:logging/logging.dart';
import 'libsql_base_dao.dart';
import 'vector_database.dart';

/// DAO for Vector Embedding operations
class VectorEmbeddingDao extends LibSqlBaseDao<VectorEmbedding> {
  static final VectorEmbeddingDao _instance = VectorEmbeddingDao._internal();
  factory VectorEmbeddingDao() => _instance;
  VectorEmbeddingDao._internal() : super('vector_embeddings');

  /// Add embedding to collection
  Future<VectorEmbedding?> addEmbedding({
    required int collectionId,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final vectorEmbedding = VectorEmbedding(
        collectionId: collectionId,
        content: content,
        embedding: embedding,
        metadata: metadata,
      );

      final id = await insert(vectorEmbedding);
      return vectorEmbedding.copyWith(id: id);
    } catch (e) {
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
      final vectorEmbeddings = embeddings.map((e) => VectorEmbedding(
        collectionId: collectionId,
        content: e.content,
        embedding: e.embedding,
        metadata: e.metadata,
      )).toList();

      await batchInsert(vectorEmbeddings);

      // Return embeddings with IDs (simulated since batchInsert doesn't return IDs)
      return vectorEmbeddings.asMap().entries.map((entry) {
        final index = entry.key;
        final embedding = entry.value;
        return embedding.copyWith(id: index + 1); // This is a simplification
      }).toList();
    } catch (e) {
      Logger.root.severe('Failed to add embeddings batch: $e');
      return [];
    }
  }

  /// Get embedding by ID
  Future<VectorEmbedding?> getEmbeddingById(int id) async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_embeddings WHERE id = ?',
        positional: [id],
      );

      if (results.isNotEmpty) {
        return VectorEmbedding.fromJson(results.first);
      }
      return null;
    } catch (e) {
      Logger.root.severe('Failed to get embedding by ID: $e');
      return null;
    }
  }

  /// Get embeddings by collection ID
  Future<List<VectorEmbedding>> getEmbeddingsByCollection({
    required int collectionId,
    int? limit,
    int? offset,
    String? contentFilter,
  }) async {
    try {
      String sql = 'SELECT * FROM vector_embeddings WHERE collection_id = ?';
      List<dynamic> params = [collectionId];

      if (contentFilter != null && contentFilter.isNotEmpty) {
        sql += ' AND content LIKE ?';
        params.add('%$contentFilter%');
      }

      sql += ' ORDER BY created_at DESC';

      if (limit != null) {
        sql += ' LIMIT ?';
        params.add(limit);
      }

      if (offset != null) {
        sql += ' OFFSET ?';
        params.add(offset);
      }

      final results = await client.query(sql, positional: params);
      return results.map((row) => VectorEmbedding.fromJson(row)).toList();
    } catch (e) {
      Logger.root.severe('Failed to get embeddings by collection: $e');
      return [];
    }
  }

  /// Search for similar embeddings using cosine similarity
  Future<List<VectorSearchResult>> searchSimilar({
    required int collectionId,
    required List<double> queryEmbedding,
    int limit = 10,
    double threshold = 0.0,
    String? contentFilter,
    Map<String, dynamic>? metadataFilter,
  }) async {
    try {
      // Get all embeddings from the collection
      String sql = 'SELECT e.*, c.name as collection_name, c.model_name FROM vector_embeddings e JOIN vector_collections c ON e.collection_id = c.id WHERE e.collection_id = ?';
      List<dynamic> params = [collectionId];

      if (contentFilter != null && contentFilter.isNotEmpty) {
        sql += ' AND e.content LIKE ?';
        params.add('%$contentFilter%');
      }

      final results = await client.query(sql, positional: params);

      // Calculate similarity scores
      final searchResults = <VectorSearchResult>[];
      final now = DateTime.now();

      for (final row in results) {
        final embeddingJson = row['embedding'] as String;
        final embedding = (jsonDecode(embeddingJson) as List)
            .map((e) => (e as num).toDouble())
            .toList();

        // Calculate cosine similarity
        final similarity = _cosineSimilarity(queryEmbedding, embedding);

        if (similarity >= threshold) {
          final vectorEmbedding = VectorEmbedding.fromJson(row);
          final collection = VectorCollection(
            id: collectionId,
            name: row['collection_name'] as String,
            dimension: embedding.length,
            modelName: row['model_name'] as String,
            createdAt: now,
            updatedAt: now,
          );

          searchResults.add(VectorSearchResult(
            embedding: vectorEmbedding,
            similarity: similarity,
            collection: collection,
          ));
        }
      }

      // Sort by similarity (descending) and limit results
      searchResults.sort((a, b) => b.similarity.compareTo(a.similarity));
      return searchResults.take(limit).toList();
    } catch (e) {
      Logger.root.severe('Failed to search similar embeddings: $e');
      return [];
    }
  }

  /// Advanced search with metadata filtering
  Future<List<VectorSearchResult>> advancedSearch({
    required VectorSearchParams params,
  }) async {
    try {
      // Get all embeddings from the collection
      String sql = '''
        SELECT e.*, c.name as collection_name, c.model_name, c.description
        FROM vector_embeddings e
        JOIN vector_collections c ON e.collection_id = c.id
        WHERE e.collection_id = ?
      ''';
      List<dynamic> queryParams = [params.collectionId];

      if (params.contentFilter != null && params.contentFilter!.isNotEmpty) {
        sql += ' AND e.content LIKE ?';
        queryParams.add('%${params.contentFilter}%');
      }

      final results = await client.query(sql, positional: queryParams);

      // Calculate similarity scores and apply filters
      final searchResults = <VectorSearchResult>[];
      final now = DateTime.now();

      for (final row in results) {
        final embeddingJson = row['embedding'] as String;
        final embedding = (jsonDecode(embeddingJson) as List)
            .map((e) => (e as num).toDouble())
            .toList();

        // Calculate cosine similarity
        final similarity = _cosineSimilarity(params.queryEmbedding, embedding);

        if (similarity >= (params.threshold ?? 0.0)) {
          // Apply metadata filter if provided
          if (params.metadataFilter != null) {
            final embeddingMetadata = row['metadata'] != null
                ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
                : <String, dynamic>{};

            if (!_matchesMetadataFilter(embeddingMetadata, params.metadataFilter!)) {
              continue;
            }
          }

          final vectorEmbedding = VectorEmbedding.fromJson(row);
          final collection = VectorCollection(
            id: params.collectionId,
            name: row['collection_name'] as String,
            description: row['description'] as String?,
            dimension: embedding.length,
            modelName: row['model_name'] as String,
            createdAt: now,
            updatedAt: now,
          );

          searchResults.add(VectorSearchResult(
            embedding: vectorEmbedding,
            similarity: similarity,
            collection: collection,
          ));
        }
      }

      // Sort by similarity (descending) and limit results
      searchResults.sort((a, b) => b.similarity.compareTo(a.similarity));
      return searchResults.take(params.limit ?? 10).toList();
    } catch (e) {
      Logger.root.severe('Failed to perform advanced search: $e');
      return [];
    }
  }

  /// Update embedding
  Future<bool> updateEmbedding(VectorEmbedding embedding) async {
    try {
      final updatedEmbedding = embedding.copyWith(updatedAt: DateTime.now());
      final affected = await update(updatedEmbedding, updatedEmbedding.id!);
      return affected > 0;
    } catch (e) {
      Logger.root.severe('Failed to update embedding: $e');
      return false;
    }
  }

  /// Delete embedding by ID
  Future<bool> deleteEmbedding(int id) async {
    try {
      final affected = await deleteWhere('id = ?', [id]);
      return affected > 0;
    } catch (e) {
      Logger.root.severe('Failed to delete embedding: $e');
      return false;
    }
  }

  /// Delete embeddings by collection ID
  Future<bool> deleteEmbeddingsByCollection(int collectionId) async {
    try {
      final affected = await deleteWhere('collection_id = ?', [collectionId]);
      return affected > 0;
    } catch (e) {
      Logger.root.severe('Failed to delete embeddings by collection: $e');
      return false;
    }
  }

  /// Get embedding count by collection
  Future<int> getEmbeddingCount(int collectionId) async {
    try {
      final result = await client.query(
        'SELECT COUNT(*) as count FROM vector_embeddings WHERE collection_id = ?',
        positional: [collectionId],
      );

      return result.first['count'] as int;
    } catch (e) {
      Logger.root.severe('Failed to get embedding count: $e');
      return 0;
    }
  }

  /// Get embeddings by content similarity (text-based search)
  Future<List<VectorEmbedding>> searchByContent({
    required int collectionId,
    required String query,
    int limit = 10,
  }) async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_embeddings WHERE collection_id = ? AND content LIKE ? ORDER BY created_at DESC LIMIT ?',
        positional: [collectionId, '%$query%', limit],
      );

      return results.map((row) => VectorEmbedding.fromJson(row)).toList();
    } catch (e) {
      Logger.root.severe('Failed to search by content: $e');
      return [];
    }
  }

  /// Calculate cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same length');
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

  /// Check if metadata matches filter conditions
  bool _matchesMetadataFilter(Map<String, dynamic> metadata, Map<String, dynamic> filter) {
    for (final entry in filter.entries) {
      final key = entry.key;
      final expectedValue = entry.value;

      if (!metadata.containsKey(key) || metadata[key] != expectedValue) {
        return false;
      }
    }
    return true;
  }

  @override
  VectorEmbedding fromJson(Map<String, dynamic> json) {
    return VectorEmbedding.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(VectorEmbedding entity) {
    return entity.toJson();
  }
}
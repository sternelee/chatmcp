import 'package:logging/logging.dart';
import 'libsql_base_dao.dart';
import 'vector_database.dart';

/// DAO for Vector Collection operations
class VectorCollectionDao extends LibSqlBaseDao<VectorCollection> {
  static final VectorCollectionDao _instance = VectorCollectionDao._internal();
  factory VectorCollectionDao() => _instance;
  VectorCollectionDao._internal() : super('vector_collections');

  /// Create a new vector collection
  Future<VectorCollection?> createCollection({
    required String name,
    String? description,
    required int dimension,
    required String modelName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final collection = VectorCollection(
        name: name,
        description: description,
        dimension: dimension,
        modelName: modelName,
        metadata: metadata,
      );

      final id = await insert(collection);
      return collection.copyWith(id: id);
    } catch (e) {
      Logger.root.severe('Failed to create vector collection: $e');
      return null;
    }
  }

  /// Get collection by ID
  Future<VectorCollection?> getCollectionById(int id) async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_collections WHERE id = ?',
        positional: [id],
      );

      if (results.isNotEmpty) {
        return VectorCollection.fromJson(results.first);
      }
      return null;
    } catch (e) {
      Logger.root.severe('Failed to get collection by ID: $e');
      return null;
    }
  }

  /// Get collection by name
  Future<VectorCollection?> getCollectionByName(String name) async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_collections WHERE name = ?',
        positional: [name],
      );

      if (results.isNotEmpty) {
        return VectorCollection.fromJson(results.first);
      }
      return null;
    } catch (e) {
      Logger.root.severe('Failed to get collection by name: $e');
      return null;
    }
  }

  /// Get all collections
  Future<List<VectorCollection>> getAllCollections() async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_collections ORDER BY created_at DESC',
      );

      return results.map((row) => VectorCollection.fromJson(row)).toList();
    } catch (e) {
      Logger.root.severe('Failed to get all collections: $e');
      return [];
    }
  }

  /// Get collections by model name
  Future<List<VectorCollection>> getCollectionsByModel(String modelName) async {
    try {
      final results = await client.query(
        'SELECT * FROM vector_collections WHERE model_name = ? ORDER BY created_at DESC',
        positional: [modelName],
      );

      return results.map((row) => VectorCollection.fromJson(row)).toList();
    } catch (e) {
      Logger.root.severe('Failed to get collections by model: $e');
      return [];
    }
  }

  /// Update collection
  Future<bool> updateCollection(VectorCollection collection) async {
    try {
      final updatedCollection = collection.copyWith(updatedAt: DateTime.now());
      final affected = await update(updatedCollection, updatedCollection.id!);
      return affected > 0;
    } catch (e) {
      Logger.root.severe('Failed to update collection: $e');
      return false;
    }
  }

  /// Delete collection by ID (will cascade delete embeddings)
  Future<bool> deleteCollection(int id) async {
    try {
      final affected = await deleteWhere('id = ?', [id]);
      return affected > 0;
    } catch (e) {
      Logger.root.severe('Failed to delete collection: $e');
      return false;
    }
  }

  /// Delete collection by name
  Future<bool> deleteCollectionByName(String name) async {
    try {
      final collection = await getCollectionByName(name);
      if (collection != null) {
        return await deleteCollection(collection.id!);
      }
      return false;
    } catch (e) {
      Logger.root.severe('Failed to delete collection by name: $e');
      return false;
    }
  }

  /// Check if collection exists
  Future<bool> collectionExists(String name) async {
    try {
      final result = await client.query(
        'SELECT COUNT(*) as count FROM vector_collections WHERE name = ?',
        positional: [name],
      );

      return result.first['count'] as int > 0;
    } catch (e) {
      Logger.root.severe('Failed to check collection existence: $e');
      return false;
    }
  }

  /// Get collection statistics
  Future<Map<String, dynamic>> getCollectionStats(int collectionId) async {
    try {
      final result = await client.query('''
        SELECT
          c.*,
          COUNT(e.id) as embedding_count,
          MIN(e.created_at) as first_embedding_at,
          MAX(e.created_at) as last_embedding_at
        FROM vector_collections c
        LEFT JOIN vector_embeddings e ON c.id = e.collection_id
        WHERE c.id = ?
        GROUP BY c.id
      ''', positional: [collectionId]);

      if (result.isNotEmpty) {
        final row = result.first;
        return {
          'collection': VectorCollection.fromJson(row),
          'embeddingCount': row['embedding_count'] as int,
          'firstEmbeddingAt': row['first_embedding_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(row['first_embedding_at'] as int)
              : null,
          'lastEmbeddingAt': row['last_embedding_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(row['last_embedding_at'] as int)
              : null,
        };
      }
      return {};
    } catch (e) {
      Logger.root.severe('Failed to get collection stats: $e');
      return {};
    }
  }

  @override
  VectorCollection fromJson(Map<String, dynamic> json) {
    return VectorCollection.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(VectorCollection entity) {
    return entity.toJson();
  }
}
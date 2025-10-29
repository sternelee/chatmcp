import 'dart:convert';
import 'package:logging/logging.dart';
import 'libsql_database.dart';

/// Vector database schema and table definitions
class VectorDatabaseSchema {
  /// Create vector collections table
  static const String createVectorCollectionsTable = '''
    CREATE TABLE IF NOT EXISTS vector_collections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      dimension INTEGER NOT NULL,
      model_name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      metadata TEXT -- JSON metadata
    )
  ''';

  /// Create vector embeddings table
  static const String createVectorEmbeddingsTable = '''
    CREATE TABLE IF NOT EXISTS vector_embeddings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      collection_id INTEGER NOT NULL,
      content TEXT NOT NULL,
      embedding BLOB NOT NULL, -- Store as JSON array of doubles
      metadata TEXT, -- JSON metadata
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (collection_id) REFERENCES vector_collections(id) ON DELETE CASCADE
    )
  ''';

  /// Create indexes for efficient querying
  static const List<String> createIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_vector_embeddings_collection_id ON vector_embeddings(collection_id)',
    'CREATE INDEX IF NOT EXISTS idx_vector_embeddings_created_at ON vector_embeddings(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_vector_collections_name ON vector_collections(name)',
  ];

  /// Initialize all tables and indexes
  static Future<void> initializeDatabase() async {
    final client = LibSqlDatabase.instance.client;

    Logger.root.info('Initializing vector database tables...');

    // Create collections table
    await client.execute(createVectorCollectionsTable);

    // Create embeddings table
    await client.execute(createVectorEmbeddingsTable);

    // Create indexes
    for (final indexSql in createIndexes) {
      await client.execute(indexSql);
    }

    Logger.root.info('Vector database initialization completed');
  }
}

/// Vector collection entity
class VectorCollection {
  final int? id;
  final String name;
  final String? description;
  final int dimension;
  final String modelName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  VectorCollection({
    this.id,
    required this.name,
    this.description,
    required this.dimension,
    required this.modelName,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.metadata,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'dimension': dimension,
      'model_name': modelName,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      if (metadata != null) 'metadata': jsonEncode(metadata),
    };
  }

  factory VectorCollection.fromJson(Map<String, dynamic> json) {
    return VectorCollection(
      id: json['id'] as int?,
      name: json['name'] as String,
      description: json['description'] as String?,
      dimension: json['dimension'] as int,
      modelName: json['model_name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
      metadata: json['metadata'] != null
          ? jsonDecode(json['metadata'] as String)
          : null,
    );
  }

  VectorCollection copyWith({
    int? id,
    String? name,
    String? description,
    int? dimension,
    String? modelName,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return VectorCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      dimension: dimension ?? this.dimension,
      modelName: modelName ?? this.modelName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Vector embedding entity
class VectorEmbedding {
  final int? id;
  final int collectionId;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  VectorEmbedding({
    this.id,
    required this.collectionId,
    required this.content,
    required this.embedding,
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'collection_id': collectionId,
      'content': content,
      'embedding': jsonEncode(embedding),
      if (metadata != null) 'metadata': jsonEncode(metadata),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory VectorEmbedding.fromJson(Map<String, dynamic> json) {
    return VectorEmbedding(
      id: json['id'] as int?,
      collectionId: json['collection_id'] as int,
      content: json['content'] as String,
      embedding: (jsonDecode(json['embedding'] as String) as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      metadata: json['metadata'] != null
          ? jsonDecode(json['metadata'] as String)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
    );
  }

  VectorEmbedding copyWith({
    int? id,
    int? collectionId,
    String? content,
    List<double>? embedding,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VectorEmbedding(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      content: content ?? this.content,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Vector search result with similarity score
class VectorSearchResult {
  final VectorEmbedding embedding;
  final double similarity;
  final VectorCollection collection;

  VectorSearchResult({
    required this.embedding,
    required this.similarity,
    required this.collection,
  });

  @override
  String toString() {
    return 'VectorSearchResult(similarity: ${similarity.toStringAsFixed(4)}, content: "${embedding.content}", collection: "${collection.name}")';
  }
}

/// Vector similarity search parameters
class VectorSearchParams {
  final int collectionId;
  final List<double> queryEmbedding;
  final int? limit;
  final double? threshold;
  final String? contentFilter;
  final Map<String, dynamic>? metadataFilter;

  VectorSearchParams({
    required this.collectionId,
    required this.queryEmbedding,
    this.limit = 10,
    this.threshold = 0.0,
    this.contentFilter,
    this.metadataFilter,
  });

  Map<String, dynamic> toJson() {
    return {
      'collection_id': collectionId,
      'query_embedding': jsonEncode(queryEmbedding),
      if (limit != null) 'limit': limit,
      if (threshold != null) 'threshold': threshold,
      if (contentFilter != null) 'content_filter': contentFilter,
      if (metadataFilter != null) 'metadata_filter': jsonEncode(metadataFilter),
    };
  }
}

/// Vector database statistics
class VectorDatabaseStats {
  final int totalCollections;
  final int totalEmbeddings;
  final Map<String, int> embeddingsByCollection;
  final List<String> availableModels;

  VectorDatabaseStats({
    required this.totalCollections,
    required this.totalEmbeddings,
    required this.embeddingsByCollection,
    required this.availableModels,
  });

  @override
  String toString() {
    return 'VectorDatabaseStats(collections: $totalCollections, embeddings: $totalEmbeddings, models: ${availableModels.length})';
  }
}
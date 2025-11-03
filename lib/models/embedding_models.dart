/// Embedding request data structure
class EmbeddingRequest {
  final String model;
  final List<String> inputs;
  final EncodingFormat? encodingFormat;
  final int? dimensions;

  EmbeddingRequest({
    required this.model,
    required this.inputs,
    this.encodingFormat,
    this.dimensions,
  });

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'inputs': inputs,
      if (encodingFormat != null) 'encoding_format': encodingFormat!.name,
      if (dimensions != null) 'dimensions': dimensions,
    };
  }
}

/// Embedding response data structure
class EmbeddingResponse {
  final String model;
  final List<EmbeddingData> data;
  final String? usage;

  EmbeddingResponse({
    required this.model,
    required this.data,
    this.usage,
  });

  factory EmbeddingResponse.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as List<dynamic>)
        .map((item) => EmbeddingData.fromJson(item as Map<String, dynamic>))
        .toList();

    return EmbeddingResponse(
      model: json['model'] as String,
      data: data,
      usage: json['usage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'data': data.map((e) => e.toJson()).toList(),
      if (usage != null) 'usage': usage,
    };
  }
}

/// Individual embedding data
class EmbeddingData {
  final List<double> embedding;
  final int index;

  EmbeddingData({
    required this.embedding,
    required this.index,
  });

  factory EmbeddingData.fromJson(Map<String, dynamic> json) {
    final embedding = (json['embedding'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    return EmbeddingData(
      embedding: embedding,
      index: json['index'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'embedding': embedding,
      'index': index,
    };
  }

  /// Get the dimension of the embedding
  int get dimension => embedding.length;
}

/// Encoding format for embeddings
enum EncodingFormat {
  float,
  base64,
}

/// Extension for encoding format
extension EncodingFormatExtension on EncodingFormat {
  String get name {
    switch (this) {
      case EncodingFormat.float:
        return 'float';
      case EncodingFormat.base64:
        return 'base64';
    }
  }
}

/// Vector embedding data structure
class VectorEmbeddingData {
  final String id;
  final List<double> embedding;
  final String content;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  VectorEmbeddingData({
    required this.id,
    required this.embedding,
    required this.content,
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory VectorEmbeddingData.fromJson(Map<String, dynamic> json) {
    final embedding = (json['embedding'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    return VectorEmbeddingData(
      id: json['id'] as String,
      embedding: embedding,
      content: json['content'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'embedding': embedding,
      'content': content,
      if (metadata != null) 'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Get the dimension of the embedding
  int get dimension => embedding.length;
}

/// Batch embedding request
class BatchEmbeddingRequest {
  final List<String> texts;
  final String model;
  final EncodingFormat? encodingFormat;
  final int? dimensions;
  final Map<String, dynamic>? metadata;

  BatchEmbeddingRequest({
    required this.texts,
    required this.model,
    this.encodingFormat,
    this.dimensions,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'texts': texts,
      'model': model,
      if (encodingFormat != null) 'encoding_format': encodingFormat!.name,
      if (dimensions != null) 'dimensions': dimensions,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Batch embedding response
class BatchEmbeddingResponse {
  final List<EmbeddingData> embeddings;
  final String model;
  final Map<String, dynamic>? usage;
  final int totalTokens;

  BatchEmbeddingResponse({
    required this.embeddings,
    required this.model,
    this.usage,
    required this.totalTokens,
  });

  factory BatchEmbeddingResponse.fromJson(Map<String, dynamic> json) {
    final embeddings = (json['embeddings'] as List<dynamic>)
        .map((item) => EmbeddingData.fromJson(item as Map<String, dynamic>))
        .toList();

    return BatchEmbeddingResponse(
      embeddings: embeddings,
      model: json['model'] as String,
      usage: json['usage'] as Map<String, dynamic>?,
      totalTokens: json['total_tokens'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'embeddings': embeddings.map((e) => e.toJson()).toList(),
      'model': model,
      if (usage != null) 'usage': usage,
      'total_tokens': totalTokens,
    };
  }
}

/// Embedding task status
enum EmbeddingTaskStatus {
  pending,
  processing,
  completed,
  failed,
}

/// Embedding task information
class EmbeddingTask {
  final String id;
  final String type; // 'single' or 'batch'
  final EmbeddingTaskStatus status;
  final String? model;
  final List<String>? texts;
  final List<EmbeddingData>? results;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;

  EmbeddingTask({
    required this.id,
    required this.type,
    required this.status,
    this.model,
    this.texts,
    this.results,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory EmbeddingTask.fromJson(Map<String, dynamic> json) {
    final results = json['results'] != null
        ? (json['results'] as List<dynamic>)
            .map((item) => EmbeddingData.fromJson(item as Map<String, dynamic>))
            .toList()
        : null;

    return EmbeddingTask(
      id: json['id'] as String,
      type: json['type'] as String,
      status: EmbeddingTaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EmbeddingTaskStatus.pending,
      ),
      model: json['model'] as String?,
      texts: (json['texts'] as List<dynamic>?)?.cast<String>(),
      results: results,
      error: json['error'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'status': status.name,
      if (model != null) 'model': model,
      if (texts != null) 'texts': texts,
      if (results != null) 'results': results!.map((e) => e.toJson()).toList(),
      if (error != null) 'error': error,
      'created_at': createdAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    };
  }

  /// Check if task is completed
  bool get isCompleted => status == EmbeddingTaskStatus.completed;

  /// Check if task failed
  bool get isFailed => status == EmbeddingTaskStatus.failed;

  /// Check if task is still processing
  bool get isProcessing => status == EmbeddingTaskStatus.pending || status == EmbeddingTaskStatus.processing;

  /// Get progress (0.0 to 1.0)
  double get progress {
    switch (status) {
      case EmbeddingTaskStatus.pending:
        return 0.0;
      case EmbeddingTaskStatus.processing:
        return 0.5; // Simplified progress
      case EmbeddingTaskStatus.completed:
        return 1.0;
      case EmbeddingTaskStatus.failed:
        return 0.0;
    }
  }
}

/// Embedding configuration
class EmbeddingConfig {
  final String model;
  final String providerId;
  final EncodingFormat encodingFormat;
  final int? dimensions;
  final int batchSize;
  final int timeoutSeconds;
  final Map<String, dynamic>? defaultMetadata;

  EmbeddingConfig({
    required this.model,
    required this.providerId,
    this.encodingFormat = EncodingFormat.float,
    this.dimensions,
    this.batchSize = 100,
    this.timeoutSeconds = 30,
    this.defaultMetadata,
  });

  factory EmbeddingConfig.fromJson(Map<String, dynamic> json) {
    return EmbeddingConfig(
      model: json['model'] as String,
      providerId: json['provider_id'] as String,
      encodingFormat: EncodingFormat.values.firstWhere(
        (e) => e.name == json['encoding_format'],
        orElse: () => EncodingFormat.float,
      ),
      dimensions: json['dimensions'] as int?,
      batchSize: json['batch_size'] as int? ?? 100,
      timeoutSeconds: json['timeout_seconds'] as int? ?? 30,
      defaultMetadata: json['default_metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'provider_id': providerId,
      'encoding_format': encodingFormat.name,
      if (dimensions != null) 'dimensions': dimensions,
      'batch_size': batchSize,
      'timeout_seconds': timeoutSeconds,
      if (defaultMetadata != null) 'default_metadata': defaultMetadata,
    };
  }

  EmbeddingConfig copyWith({
    String? model,
    String? providerId,
    EncodingFormat? encodingFormat,
    int? dimensions,
    int? batchSize,
    int? timeoutSeconds,
    Map<String, dynamic>? defaultMetadata,
  }) {
    return EmbeddingConfig(
      model: model ?? this.model,
      providerId: providerId ?? this.providerId,
      encodingFormat: encodingFormat ?? this.encodingFormat,
      dimensions: dimensions ?? this.dimensions,
      batchSize: batchSize ?? this.batchSize,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      defaultMetadata: defaultMetadata ?? this.defaultMetadata,
    );
  }
}
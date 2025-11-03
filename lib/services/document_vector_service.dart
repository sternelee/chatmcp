import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/embedding_service.dart';
import '../services/vector_database_service.dart';
import '../dao/vector_database.dart';

/// Document processing status
enum DocumentProcessingStatus { idle, reading, parsing, vectorizing, saving, completed, error }

/// Document information
class DocumentInfo {
  final String id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String fileType;
  final DateTime createdAt;
  final String? content;
  final int? vectorCount;
  final DocumentProcessingStatus status;
  final String? errorMessage;

  DocumentInfo({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.fileType,
    required this.createdAt,
    this.content,
    this.vectorCount,
    this.status = DocumentProcessingStatus.idle,
    this.errorMessage,
  });

  factory DocumentInfo.fromFile(File file) {
    return DocumentInfo(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: path.basename(file.path),
      filePath: file.path,
      fileSize: file.lengthSync(),
      fileType: path.extension(file.path).toLowerCase(),
      createdAt: DateTime.now(),
    );
  }

  DocumentInfo copyWith({
    String? id,
    String? fileName,
    String? filePath,
    int? fileSize,
    String? fileType,
    DateTime? createdAt,
    String? content,
    int? vectorCount,
    DocumentProcessingStatus? status,
    String? errorMessage,
  }) {
    return DocumentInfo(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      fileType: fileType ?? this.fileType,
      createdAt: createdAt ?? this.createdAt,
      content: content ?? this.content,
      vectorCount: vectorCount ?? this.vectorCount,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String get statusText {
    switch (status) {
      case DocumentProcessingStatus.idle:
        return 'Waiting';
      case DocumentProcessingStatus.reading:
        return 'Reading...';
      case DocumentProcessingStatus.parsing:
        return 'Parsing...';
      case DocumentProcessingStatus.vectorizing:
        return 'Vectorizing...';
      case DocumentProcessingStatus.saving:
        return 'Saving...';
      case DocumentProcessingStatus.completed:
        return 'Completed';
      case DocumentProcessingStatus.error:
        return 'Error: ${errorMessage ?? 'Unknown error'}';
    }
  }
}

/// Document chunk for vectorization
class DocumentChunk {
  final String content;
  final Map<String, dynamic> metadata;

  DocumentChunk({required this.content, required this.metadata});
}

/// Document processing configuration
class DocumentProcessingConfig {
  final String collectionName;
  final String modelName;
  final int chunkSize;
  final int chunkOverlap;
  final Map<String, dynamic> metadata;

  const DocumentProcessingConfig({
    required this.collectionName,
    required this.modelName,
    this.chunkSize = 500,
    this.chunkOverlap = 50,
    this.metadata = const {},
  });
}

/// Service for document processing and vectorization
class DocumentVectorService {
  static final DocumentVectorService _instance = DocumentVectorService._internal();
  factory DocumentVectorService() => _instance;
  DocumentVectorService._internal();

  static final Logger _logger = Logger.root;
  final VectorDatabaseService _vectorService = VectorDatabaseService();

  /// Supported file types
  static const supportedFileTypes = ['.txt', '.md', '.pdf', '.docx', '.doc', '.rtf', '.html', '.htm', '.json', '.xml', '.csv'];

  /// Process documents and vectorize them
  Future<List<DocumentInfo>> processDocuments({
    required List<DocumentInfo> documents,
    required DocumentProcessingConfig config,
    Function(DocumentInfo)? onProgress,
  }) async {
    final processedDocuments = <DocumentInfo>[];

    // Ensure collection exists
    final collection = await _vectorService.getOrCreateCollection(
      name: config.collectionName,
      description: 'Documents imported on ${DateTime.now().toIso8601String()}',
      modelName: config.modelName,
      metadata: {'source': 'document_import', 'auto_created': true},
    );

    if (collection == null) {
      _logger.severe('Failed to create or get collection: ${config.collectionName}');
      return documents.map((doc) => doc.copyWith(status: DocumentProcessingStatus.error, errorMessage: 'Failed to create collection')).toList();
    }

    for (final document in documents) {
      try {
        onProgress?.call(document.copyWith(status: DocumentProcessingStatus.reading));

        // Read document content
        final content = await _readDocument(document);
        if (content == null || content.isEmpty) {
          processedDocuments.add(
            document.copyWith(status: DocumentProcessingStatus.error, errorMessage: 'Failed to read document or document is empty'),
          );
          continue;
        }

        onProgress?.call(document.copyWith(status: DocumentProcessingStatus.parsing, content: content));

        // Parse document into chunks
        final chunks = _parseDocument(content, document, config);
        if (chunks.isEmpty) {
          processedDocuments.add(document.copyWith(status: DocumentProcessingStatus.error, errorMessage: 'Failed to parse document into chunks'));
          continue;
        }

        onProgress?.call(document.copyWith(status: DocumentProcessingStatus.vectorizing, content: content));

        // Generate embeddings for chunks
        final chunkTexts = chunks.map((chunk) => chunk.content).toList();
        final embeddingResponse = await EmbeddingService.createEmbeddings(texts: chunkTexts, model: config.modelName);

        if (embeddingResponse == null || embeddingResponse.data.isEmpty) {
          processedDocuments.add(document.copyWith(status: DocumentProcessingStatus.error, errorMessage: 'Failed to generate embeddings'));
          continue;
        }

        onProgress?.call(document.copyWith(status: DocumentProcessingStatus.saving, content: content, vectorCount: chunks.length));

        // Save to vector database
        final vectorEmbeddings = <VectorEmbedding>[];
        for (final entry in chunks.asMap().entries) {
          final index = entry.key;
          final chunk = entry.value;

          final embedding = await _vectorService.addTextEmbedding(
            collectionName: config.collectionName,
            text: chunk.content,
            metadata: {
              ...config.metadata,
              ...chunk.metadata,
              'document_id': document.id,
              'document_name': document.fileName,
              'document_type': document.fileType,
              'chunk_index': index,
            },
          );

          if (embedding != null) {
            vectorEmbeddings.add(embedding);
          }
        }

        if (vectorEmbeddings.isNotEmpty) {
          processedDocuments.add(
            document.copyWith(status: DocumentProcessingStatus.completed, content: content, vectorCount: vectorEmbeddings.length),
          );
          _logger.info('Successfully processed document: ${document.fileName} (${vectorEmbeddings.length} chunks)');
        } else {
          processedDocuments.add(document.copyWith(status: DocumentProcessingStatus.error, errorMessage: 'Failed to save embeddings to database'));
        }
      } catch (e, stackTrace) {
        _logger.severe('Failed to process document ${document.fileName}: $e', stackTrace);
        processedDocuments.add(document.copyWith(status: DocumentProcessingStatus.error, errorMessage: e.toString()));
      }
    }

    return processedDocuments;
  }

  /// Read document content
  Future<String?> _readDocument(DocumentInfo document) async {
    try {
      if (kIsWeb) {
        // Web implementation
        return await _readWebDocument(document);
      } else {
        // Desktop implementation
        final file = File(document.filePath);
        if (!await file.exists()) {
          _logger.warning('File does not exist: ${document.filePath}');
          return null;
        }

        switch (document.fileType) {
          case '.txt':
          case '.md':
            return await file.readAsString(encoding: utf8);
          case '.json':
            final content = await file.readAsString(encoding: utf8);
            // Extract text from JSON
            return _extractTextFromJson(content);
          case '.csv':
            return await file.readAsString(encoding: utf8);
          case '.html':
          case '.htm':
            return _extractTextFromHtml(await file.readAsString(encoding: utf8));
          default:
            _logger.warning('Unsupported file type for reading: ${document.fileType}');
            return await _readAsText(file);
        }
      }
    } catch (e) {
      _logger.severe('Error reading document ${document.fileName}: $e');
      return null;
    }
  }

  /// Read document on web platform
  Future<String?> _readWebDocument(DocumentInfo document) async {
    // For web platform, we'd need to handle file differently
    // This is a simplified implementation
    try {
      final bytes = base64.decode(document.filePath.split(',').last);
      return utf8.decode(bytes);
    } catch (e) {
      _logger.severe('Error reading web document: $e');
      return null;
    }
  }

  /// Parse document into chunks
  List<DocumentChunk> _parseDocument(String content, DocumentInfo document, DocumentProcessingConfig config) {
    if (content.trim().isEmpty) return [];

    final chunks = <DocumentChunk>[];
    final words = content.split(RegExp(r'\s+'));

    for (int i = 0; i < words.length; i += config.chunkSize - config.chunkOverlap) {
      final endIndex = (i + config.chunkSize).clamp(0, words.length);
      final chunkWords = words.sublist(i, endIndex);

      if (chunkWords.isNotEmpty) {
        final chunkContent = chunkWords.join(' ');
        chunks.add(
          DocumentChunk(
            content: chunkContent,
            metadata: {'chunk_start': i, 'chunk_end': endIndex, 'word_count': chunkWords.length, 'char_count': chunkContent.length},
          ),
        );
      }

      if (endIndex >= words.length) break;
    }

    return chunks;
  }

  /// Extract text from JSON
  String _extractTextFromJson(String jsonContent) {
    try {
      final data = jsonDecode(jsonContent);
      return _extractTextFromJsonValue(data);
    } catch (e) {
      _logger.warning('Failed to parse JSON: $e');
      return jsonContent;
    }
  }

  /// Recursively extract text from JSON value
  String _extractTextFromJsonValue(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      return value.values.map((v) => _extractTextFromJsonValue(v)).join(' ');
    }
    if (value is List) {
      return value.map((v) => _extractTextFromJsonValue(v)).join(' ');
    }
    return value.toString();
  }

  /// Extract text from HTML
  String _extractTextFromHtml(String htmlContent) {
    // Simple HTML tag removal
    final cleanText = htmlContent.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleanText;
  }

  /// Try to read file as text (fallback)
  Future<String> _readAsText(File file) async {
    try {
      return await file.readAsString(encoding: utf8);
    } catch (e) {
      _logger.warning('Failed to read file as text: $e');
      return '';
    }
  }

  /// Pick documents from file system
  Future<List<File>> pickDocuments() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedFileTypes.map((e) => e.substring(1)).toList(),
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final files = <File>[];
        for (final file in result.files) {
          if (file.path != null) {
            files.add(File(file.path!));
          }
        }
        return files;
      }
      return [];
    } catch (e) {
      _logger.severe('Error picking documents: $e');
      return [];
    }
  }

  /// Create document info objects from files
  List<DocumentInfo> createDocumentInfos(List<File> files) {
    return files.map((file) => DocumentInfo.fromFile(file)).toList();
  }

  /// Check if file type is supported
  bool isFileTypeSupported(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    return supportedFileTypes.contains(extension);
  }

  /// Get supported file types for UI
  List<String> getSupportedFileTypes() {
    return supportedFileTypes;
  }

  /// Delete document vectors from collection
  Future<bool> deleteDocumentVectors({required String collectionName, required String documentId}) async {
    try {
      // Get collection
      final collection = await _vectorService.getCollection(collectionName);
      if (collection == null) return false;

      // Get all embeddings with document_id metadata
      // Note: This would require metadata search capability in vector database
      // For now, we'll implement a simple approach
      final embeddings = await _vectorService.getEmbeddings(collectionName: collectionName, contentFilter: documentId);

      // Delete each embedding
      for (final embedding in embeddings) {
        if (embedding.id != null) {
          await _vectorService.deleteEmbedding(embedding.id!);
        }
      }

      _logger.info('Deleted ${embeddings.length} vectors for document: $documentId');
      return true;
    } catch (e) {
      _logger.severe('Failed to delete document vectors: $e');
      return false;
    }
  }

  /// Get processing statistics
  Future<Map<String, dynamic>> getProcessingStatistics() async {
    try {
      final stats = await _vectorService.getDatabaseStats();
      return {
        'totalCollections': stats.totalCollections,
        'totalEmbeddings': stats.totalEmbeddings,
        'availableModels': stats.availableModels,
        'embeddingsByCollection': stats.embeddingsByCollection,
        'supportedFileTypes': supportedFileTypes,
      };
    } catch (e) {
      _logger.severe('Failed to get processing statistics: $e');
      return {};
    }
  }
}


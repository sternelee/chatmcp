import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import '../../provider/knowledge_base_provider.dart';
import '../../services/document_vector_service.dart';

/// Knowledge Base Configuration Page
class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _collectionNameController = TextEditingController();
  final _collectionDescriptionController = TextEditingController();
  final _searchController = TextEditingController();
  static final Logger _logger = Logger.root;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _collectionNameController.dispose();
    _collectionDescriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final provider = Provider.of<KnowledgeBaseProvider>(context, listen: false);
    await provider.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KnowledgeBaseProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Knowledge Base'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Collections', icon: Icon(Icons.folder)),
                Tab(text: 'Import', icon: Icon(Icons.upload_file)),
                Tab(text: 'Search', icon: Icon(Icons.search)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _refreshData(provider),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildCollectionsTab(provider),
              _buildImportTab(provider),
              _buildSearchTab(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionsTab(KnowledgeBaseProvider provider) {
    return Column(
      children: [
        // Statistics Cards
        if (provider.statistics.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Collections',
                    provider.statistics['totalCollections']?.toString() ?? '0',
                    Icons.folder,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Embeddings',
                    provider.statistics['totalEmbeddings']?.toString() ?? '0',
                    Icons.grain,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Models',
                    provider.statistics['availableModels']?.length.toString() ?? '0',
                    Icons.psychology,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ),
        // Collections List
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.collections.isEmpty
                  ? _buildEmptyState('No collections found', 'Create your first knowledge base collection')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.collections.length,
                      itemBuilder: (context, index) {
                        final collection = provider.collections[index];
                        return _buildCollectionCard(provider, collection);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionCard(KnowledgeBaseProvider provider, collection) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Icon(Icons.folder, color: Colors.blue.shade700),
        ),
        title: Text(collection.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (collection.description != null)
              Text(
                collection.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${collection.dimension}D',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  collection.modelName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleCollectionAction(provider, collection, value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'select',
              child: ListTile(
                leading: Icon(Icons.check_circle),
                title: Text('Select'),
                dense: true,
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('Edit'),
                dense: true,
              ),
            ),
            const PopupMenuItem(
              value: 'stats',
              child: ListTile(
                leading: Icon(Icons.analytics),
                title: Text('Statistics'),
                dense: true,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                dense: true,
              ),
            ),
          ],
        ),
        onTap: () => _selectCollection(provider, collection.name),
      ),
    );
  }

  Widget _buildImportTab(KnowledgeBaseProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Configuration Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import Configuration',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: provider.currentCollectionName.isEmpty ? null : provider.currentCollectionName,
                    decoration: const InputDecoration(
                      labelText: 'Target Collection',
                      border: OutlineInputBorder(),
                    ),
                    items: provider.collections.map((collection) {
                      return DropdownMenuItem(
                        value: collection.name,
                        child: Text(collection.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateConfiguration(collectionName: value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: provider.currentModelName,
                    decoration: const InputDecoration(
                      labelText: 'Embedding Model',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'text-embedding-3-small', child: Text('text-embedding-3-small')),
                      DropdownMenuItem(value: 'text-embedding-3-large', child: Text('text-embedding-3-large')),
                      DropdownMenuItem(value: 'text-embedding-ada-002', child: Text('text-embedding-ada-002')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateConfiguration(modelName: value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: provider.chunkSize.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Chunk Size',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final size = int.tryParse(value);
                            if (size != null && size > 0) {
                              provider.updateConfiguration(chunkSize: size);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: provider.chunkOverlap.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Chunk Overlap',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final overlap = int.tryParse(value);
                            if (overlap != null && overlap >= 0) {
                              provider.updateConfiguration(chunkOverlap: overlap);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showCreateCollectionDialog(provider),
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Collection'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Document Selection Section
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Documents (${provider.selectedDocuments.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _pickDocuments(provider),
                              icon: const Icon(Icons.file_upload),
                              label: const Text('Pick Files'),
                            ),
                            const SizedBox(width: 8),
                            if (provider.selectedDocuments.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _importDocuments(provider),
                                icon: provider.isProcessing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.cloud_upload),
                                label: Text(provider.isProcessing ? 'Processing...' : 'Import'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Supported file types
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supported file types:',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: provider.getSupportedFileTypes().map((type) {
                              return Chip(
                                label: Text(type),
                                backgroundColor: Colors.blue.shade100,
                                labelStyle: const TextStyle(fontSize: 12),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Selected documents list
                    Expanded(
                      child: provider.selectedDocuments.isEmpty
                          ? _buildEmptyState(
                              'No documents selected',
                              'Pick files to import into your knowledge base',
                            )
                          : ListView.builder(
                              itemCount: provider.selectedDocuments.length,
                              itemBuilder: (context, index) {
                                final document = provider.selectedDocuments[index];
                                return _buildDocumentItem(provider, document, index);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentItem(KnowledgeBaseProvider provider, DocumentInfo document, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getFileTypeColor(document.fileType),
          child: Icon(
            _getFileTypeIcon(document.fileType),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(document.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.formattedFileSize),
            Row(
              children: [
                Text(
                  document.statusText,
                  style: TextStyle(
                    color: _getStatusColor(document.status),
                    fontSize: 12,
                  ),
                ),
                if (document.vectorCount != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${document.vectorCount} chunks',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle, color: Colors.red),
          onPressed: () => _removeDocument(provider, document.id),
          tooltip: 'Remove',
        ),
      ),
    );
  }

  Widget _buildSearchTab(KnowledgeBaseProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Search Input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: provider.currentCollectionName.isEmpty ? null : provider.currentCollectionName,
                    decoration: const InputDecoration(
                      labelText: 'Search Collection',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder),
                    ),
                    items: provider.collections.map((collection) {
                      return DropdownMenuItem(
                        value: collection.name,
                        child: Text(collection.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        provider.updateConfiguration(collectionName: value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Query',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      ),
                    ),
                    onSubmitted: (value) => _performSearch(provider, value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: 0.3,
                          divisions: 10,
                          min: 0.0,
                          max: 1.0,
                          label: 'Similarity Threshold',
                          onChanged: (value) {},
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _performSearch(provider, _searchController.text),
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Search Results
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search Results',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Enter a search query to find similar content',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getFileTypeColor(String fileType) {
    switch (fileType) {
      case '.txt':
      case '.md':
        return Colors.blue;
      case '.pdf':
        return Colors.red;
      case '.docx':
      case '.doc':
        return Colors.blue.shade700;
      case '.json':
      case '.xml':
        return Colors.green;
      case '.html':
      case '.htm':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileTypeIcon(String fileType) {
    switch (fileType) {
      case '.txt':
      case '.md':
        return Icons.text_snippet;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.docx':
      case '.doc':
        return Icons.description;
      case '.json':
      case '.xml':
        return Icons.code;
      case '.html':
      case '.htm':
        return Icons.language;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getStatusColor(DocumentProcessingStatus status) {
    switch (status) {
      case DocumentProcessingStatus.completed:
        return Colors.green;
      case DocumentProcessingStatus.error:
        return Colors.red;
      case DocumentProcessingStatus.reading:
      case DocumentProcessingStatus.parsing:
      case DocumentProcessingStatus.vectorizing:
      case DocumentProcessingStatus.saving:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _refreshData(KnowledgeBaseProvider provider) async {
    await provider.initialize();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data refreshed')),
      );
    }
  }

  void _selectCollection(KnowledgeBaseProvider provider, String collectionName) {
    provider.updateConfiguration(collectionName: collectionName);
    _tabController.animateTo(2); // Switch to search tab
  }

  void _handleCollectionAction(KnowledgeBaseProvider provider, collection, String action) {
    switch (action) {
      case 'select':
        _selectCollection(provider, collection.name);
        break;
      case 'edit':
        _showEditCollectionDialog(provider, collection);
        break;
      case 'stats':
        _showCollectionStats(provider, collection.name);
        break;
      case 'delete':
        _showDeleteConfirmationDialog(provider, collection.name);
        break;
    }
  }

  Future<void> _showCreateCollectionDialog(KnowledgeBaseProvider provider) async {
    _collectionNameController.clear();
    _collectionDescriptionController.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Knowledge Base'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _collectionNameController,
              decoration: const InputDecoration(
                labelText: 'Collection Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _collectionDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true && _collectionNameController.text.isNotEmpty) {
      await provider.createKnowledgeBase(
        name: _collectionNameController.text,
        description: _collectionDescriptionController.text.isEmpty
            ? null
            : _collectionDescriptionController.text,
      );
    }
  }

  Future<void> _showEditCollectionDialog(KnowledgeBaseProvider provider, collection) async {
    _collectionNameController.text = collection.name;
    _collectionDescriptionController.text = collection.description ?? '';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _collectionNameController,
              decoration: const InputDecoration(
                labelText: 'Collection Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _collectionDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      await provider.updateCollectionMetadata(
        collectionName: collection.name,
        description: _collectionDescriptionController.text.isEmpty
            ? null
            : _collectionDescriptionController.text,
        metadata: {'last_edited': DateTime.now().toIso8601String()},
      );
    }
  }

  Future<void> _showCollectionStats(KnowledgeBaseProvider provider, String collectionName) async {
    final stats = await provider.getCollectionStats(collectionName);
    if (stats != null && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Collection Statistics: $collectionName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${stats['name']}'),
              Text('Description: ${stats['description'] ?? 'No description'}'),
              Text('Model: ${stats['modelName']}'),
              Text('Dimension: ${stats['dimension']}D'),
              Text('Documents: ${stats['documentCount']}'),
              Text('Created: ${_formatDate(stats['createdAt'])}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmationDialog(KnowledgeBaseProvider provider, String collectionName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection'),
        content: Text('Are you sure you want to delete the collection "$collectionName"? This will also delete all embedded documents in this collection.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      final success = await provider.deleteKnowledgeBase(collectionName);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection deleted successfully')),
        );
      }
    }
  }

  Future<void> _pickDocuments(KnowledgeBaseProvider provider) async {
    await provider.pickDocuments();
  }

  Future<void> _importDocuments(KnowledgeBaseProvider provider) async {
    if (provider.currentCollectionName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target collection')),
      );
      return;
    }

    final success = await provider.importDocuments(
      collectionName: provider.currentCollectionName,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Documents imported successfully' : 'Failed to import documents'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _removeDocument(KnowledgeBaseProvider provider, String documentId) {
    provider.removeDocument(documentId);
  }

  Future<void> _performSearch(KnowledgeBaseProvider provider, String query) async {
    if (query.trim().isEmpty || provider.currentCollectionName.isEmpty) {
      return;
    }

    final results = await provider.searchKnowledgeBase(
      collectionName: provider.currentCollectionName,
      queryText: query,
      limit: 10,
      threshold: 0.3,
    );

    if (mounted) {
      // Update search results UI (implement as needed)
      _logger.info('Search found ${results.length} results');
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year}';
  }
}
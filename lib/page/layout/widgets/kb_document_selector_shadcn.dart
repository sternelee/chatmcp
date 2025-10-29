import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../provider/provider_manager.dart';
import '../../../widgets/ink_icon.dart';

/// Knowledge Base document selector widget with shadcn/ui inspired design
class KbDocumentSelector extends StatefulWidget {
  final bool disabled;
  final Function(String selectedDocument) onDocumentSelected;

  const KbDocumentSelector({
    super.key,
    required this.disabled,
    required this.onDocumentSelected,
  });

  @override
  State<KbDocumentSelector> createState() => _KbDocumentSelectorState();
}

class _KbDocumentSelectorState extends State<KbDocumentSelector> {
  String _selectedCollection = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final kbProvider = ProviderManager.knowledgeBaseProvider;
    await kbProvider.initialize();

    if (mounted && kbProvider.collections.isNotEmpty) {
      setState(() {
        _selectedCollection = kbProvider.collections.first.name;
      });
    }
  }

  Future<void> _searchDocuments(String query) async {
    if (query.trim().isEmpty || _selectedCollection.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final kbProvider = ProviderManager.knowledgeBaseProvider;
      final results = await kbProvider.searchKnowledgeBase(
        collectionName: _selectedCollection,
        queryText: query,
        limit: 10,
        threshold: 0.2,
      );

      if (mounted) {
        setState(() {
          _searchResults = results.map((result) => {
            'id': result.embedding.id.toString(),
            'content': result.embedding.content,
            'metadata': result.embedding.metadata,
            'similarity': result.similarity,
          }).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _showDocumentSelector() {
    if (widget.disabled) return;

    showDialog(
      context: context,
      builder: (context) => _buildShadcnDialog(),
    );
  }

  Widget _buildShadcnDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 640,
        height: 600,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_stories,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Knowledge Base Documents',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Search and add relevant documents to your conversation',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildSearchSection(),
            const SizedBox(height: 24),
            _buildResultsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Consumer<ProviderManager>(
      builder: (context, providerManager, child) {
        final kbProvider = ProviderManager.knowledgeBaseProvider;

        if (kbProvider.collections.isEmpty) {
          return _buildEmptyCollectionsCard();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Collection selector
            Text(
              'Collection',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            _buildCollectionSelector(kbProvider),
            const SizedBox(height: 16),

            // Search input
            Text(
              'Search Documents',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            _buildSearchInput(),
          ],
        );
      },
    );
  }

  Widget _buildEmptyCollectionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_amber,
              color: Colors.orange.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No knowledge base collections found. Please create a collection and import documents first.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionSelector(kbProvider) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCollection.isEmpty ? null : _selectedCollection,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: BorderRadius.circular(8),
          items: kbProvider.collections.map((collection) {
            return DropdownMenuItem(
              value: collection.name,
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      collection.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedCollection = value;
                _searchResults.clear();
                _searchController.clear();
              });
            }
          },
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _searchFocusNode.hasFocus
              ? Theme.of(context).primaryColor
              : Theme.of(context).dividerColor,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Search for documents...',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        style: Theme.of(context).textTheme.bodyMedium,
        onChanged: (value) {
          if (value.trim().isNotEmpty) {
            _searchDocuments(value);
          } else {
            setState(() {
              _searchResults = [];
            });
          }
        },
        onSubmitted: _searchDocuments,
      ),
    );
  }

  Widget _buildResultsSection() {
    return Expanded(
      child: _isSearching
          ? _buildLoadingState()
          : _searchResults.isEmpty
              ? _buildEmptyState()
              : _buildSearchResults(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Searching documents...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try using different keywords or check your collection',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_searchResults.length} results found',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _searchResults.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final result = _searchResults[index];
              return _buildDocumentResult(result);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentResult(Map<String, dynamic> result) {
    final content = result['content'] as String;
    final metadata = result['metadata'] as Map<String, dynamic>?;
    final similarity = result['similarity'] as double;

    // Extract document info from metadata
    final documentName = metadata?['document_name'] as String? ?? 'Unknown Document';
    final chunkIndex = metadata?['chunk_index'] as int? ?? 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          widget.onDocumentSelected(content);
          Navigator.of(context).pop();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            documentName,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getSimilarityColor(similarity),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(similarity * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chunk ${chunkIndex + 1}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      content.length > 200
                          ? '${content.substring(0, 200)}...'
                          : content,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.add_circle_outline,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSimilarityColor(double similarity) {
    if (similarity >= 0.8) return Colors.green;
    if (similarity >= 0.6) return Colors.blue;
    if (similarity >= 0.4) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return InkIcon(
      icon: Icons.auto_stories,
      onTap: widget.disabled ? null : _showDocumentSelector,
      disabled: widget.disabled,
      hoverColor: Theme.of(context).hoverColor,
      tooltip: 'Knowledge Base Documents',
    );
  }
}
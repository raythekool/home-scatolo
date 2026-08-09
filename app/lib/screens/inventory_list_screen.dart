import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/item.dart';
import '../services/storage_service.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key, this.containerId, this.title});

  final int? containerId;
  final String? title;

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  final StorageService _storage = StorageService();
  final TextEditingController _searchController = TextEditingController();
  List<Item> _items = <Item>[];
  String _query = '';
  String? _category;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final List<Item> items = widget.containerId == null
        ? await _storage.getAllItems()
        : await _storage.getItems(widget.containerId!);
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  List<Item> get _visibleItems {
    final String query = _query.trim().toLowerCase();
    return _items.where((Item item) {
      final bool matchesQuery = query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);
      return matchesQuery && (_category == null || item.category == _category);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> categories =
        _items.map((Item item) => item.category).toSet().toList()..sort();
    final List<Item> items = _visibleItems;
    final String title = widget.title ?? 'Inventario';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title),
            Text(
              widget.containerId == null ? 'Tutti gli oggetti' : 'Contenitore',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scansiona un oggetto',
        onPressed: () => context.go(
          widget.containerId == null
              ? '/capture'
              : '/capture?containerId=${widget.containerId}',
        ),
        child: const Icon(Icons.document_scanner_outlined),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (String value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Cerca oggetti',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 42,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Tutti'),
                            selected: _category == null,
                            onSelected: (_) => setState(() => _category = null),
                          ),
                        ),
                        ...categories.map(
                          (String category) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _category == category,
                              onSelected: (_) => setState(
                                () => _category =
                                    _category == category ? null : category,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: items.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) =>
                              _InventoryRow(item: items[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final bool filtering = _query.isNotEmpty || _category != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              filtering
                  ? Icons.manage_search_outlined
                  : Icons.inventory_2_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              filtering
                  ? 'Nessun oggetto corrisponde'
                  : 'Qui c\'è ancora spazio',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              filtering
                  ? 'Prova a modificare la ricerca o il filtro.'
                  : 'Scansiona il primo oggetto per iniziare l’inventario.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(_iconForCategory(item.category)),
        ),
        title: Text(item.name),
        subtitle: Text(item.category),
        trailing: Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'x${item.quantity}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(String category) {
    return switch (category.toLowerCase()) {
      'elettronica' => Icons.cable_outlined,
      'documenti' => Icons.description_outlined,
      'cucina' => Icons.kitchen_outlined,
      'casa' => Icons.lightbulb_outline,
      _ => Icons.inventory_2_outlined,
    };
  }
}

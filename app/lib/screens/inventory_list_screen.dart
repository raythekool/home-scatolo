import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/container.dart' as models;
import '../models/house.dart';
import '../models/item.dart';
import '../models/room.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({
    super.key,
    this.containerId,
    this.title,
    this.storageService,
  });

  final int? containerId;
  final String? title;
  final StorageService? storageService;

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final TextEditingController _searchController = TextEditingController();
  List<Item> _items = <Item>[];
  String? _resolvedTitle;
  String? _resolvedSubtitle;
  String _query = '';
  String? _category;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void didUpdateWidget(InventoryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.containerId != widget.containerId) {
      _loadItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final List<Item> items = widget.containerId == null
          ? await _storage.getAllItems()
          : await _storage.getItems(widget.containerId!);
      final (String? resolvedTitle, String? resolvedSubtitle) =
          await _resolveContainerHeader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _resolvedTitle = resolvedTitle;
        _resolvedSubtitle = resolvedSubtitle;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare l\'inventario. Riprova.';
      });
    }
  }

  Future<(String?, String?)> _resolveContainerHeader() async {
    final int? containerId = widget.containerId;
    if (containerId == null) return (null, null);
    try {
      final List<models.Container> containers =
          await _storage.getAllContainers();
      models.Container? target;
      for (final models.Container c in containers) {
        if (c.id == containerId) {
          target = c;
          break;
        }
      }
      if (target == null) return (null, null);

      String subtitle = target.type.toValue();
      try {
        final List<House> houses = await _storage.getHouses();
        for (final House house in houses) {
          final int? houseId = house.id;
          if (houseId == null) continue;
          final List<Room> rooms = await _storage.getRooms(houseId);
          for (final Room room in rooms) {
            if (room.id == target.roomId) {
              subtitle =
                  '${house.name} › ${room.name} · ${target.type.toValue()}';
              return (target.name, subtitle);
            }
          }
        }
      } catch (_) {
        // Optional room/house lookup.
      }
      return (target.name, subtitle);
    } catch (_) {
      return (null, null);
    }
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
    final String title = widget.title ?? _resolvedTitle ?? 'Inventario';
    final String subtitle = _resolvedSubtitle ??
        (widget.containerId == null ? 'Tutti gli oggetti' : 'Contenitore');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: <Widget>[
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cerca in tutta la casa',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scansiona un oggetto',
        onPressed: () => context.push(
          widget.containerId == null
              ? '/capture'
              : '/capture?containerId=${widget.containerId}',
        ),
        child: const Icon(Icons.document_scanner_outlined),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loadItems,
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (String value) =>
                              setState(() => _query = value),
                          decoration: InputDecoration(
                            labelText: 'Filtra oggetti',
                            hintText: 'Cerca oggetti',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Pulisci filtro',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      if (categories.isNotEmpty)
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('Tutti'),
                                  selected: _category == null,
                                  onSelected: (_) =>
                                      setState(() => _category = null),
                                ),
                              ),
                              ...categories.map(
                                (String category) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category),
                                    selected: _category == category,
                                    onSelected: (_) => setState(
                                      () => _category = _category == category
                                          ? null
                                          : category,
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
                            : RefreshIndicator(
                                onRefresh: _loadItems,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 96),
                                  itemCount: items.length,
                                  separatorBuilder:
                                      (BuildContext context, int index) =>
                                          const SizedBox(height: 10),
                                  itemBuilder:
                                      (BuildContext context, int index) =>
                                          _InventoryRow(
                                    item: items[index],
                                    onTap: items[index].id == null
                                        ? null
                                        : () async {
                                            await context.push(
                                              '/items/${items[index].id}',
                                            );
                                            if (mounted) _loadItems();
                                          },
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final bool filtering = _query.isNotEmpty || _category != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    : 'Scansiona il primo oggetto per iniziare l\'inventario.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (filtering)
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _category = null;
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Pulisci filtri'),
                )
              else
                FilledButton.icon(
                  onPressed: () => context.push(
                    widget.containerId == null
                        ? '/capture'
                        : '/capture?containerId=${widget.containerId}',
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scansiona primo oggetto'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.item, this.onTap});

  final Item item;
  final VoidCallback? onTap;

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
        onTap: onTap,
        trailing: Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'x${item.quantity}',
            semanticsLabel: 'Quantità ${item.quantity}',
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

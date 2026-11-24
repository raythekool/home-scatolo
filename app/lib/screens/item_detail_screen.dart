import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/container.dart' as models;
import '../models/house.dart';
import '../models/item.dart';
import '../models/item_location.dart';
import '../models/room.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.itemId,
    this.storageService,
  });

  final String itemId;
  final StorageService? storageService;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late final StorageService _storage =
      widget.storageService ?? createStorageService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  ItemLocation? _location;
  List<models.Container> _containers = <models.Container>[];
  Map<int, String> _containerPathById = const <int, String>{};
  int? _selectedContainerId;
  int _quantity = 1;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _nameError;
  String? _categoryError;

  String _initialName = '';
  String _initialCategory = '';
  String _initialDescription = '';
  int? _initialContainerId;
  int _initialQuantity = 1;

  bool get _isDirty {
    if (_location == null) return false;
    return _nameController.text.trim() != _initialName ||
        _categoryController.text.trim() != _initialCategory ||
        _descriptionController.text.trim() != _initialDescription ||
        _selectedContainerId != _initialContainerId ||
        _quantity != _initialQuantity;
  }

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  @override
  void didUpdateWidget(ItemDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemId != widget.itemId) {
      _loadItem();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadItem() async {
    final int? parsedId = int.tryParse(widget.itemId);
    if (parsedId == null || parsedId <= 0) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Identificativo oggetto non valido.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ItemLocation? location = await _storage.getItemLocation(parsedId);
      final List<models.Container> containers =
          await _storage.getAllContainers();
      final Map<int, String> pathMap = await _buildContainerPaths(containers);
      if (!mounted) return;
      if (location == null) {
        setState(() {
          _location = null;
          _isLoading = false;
          _errorMessage = 'Oggetto non trovato.';
        });
        return;
      }

      _nameController.text = location.item.name;
      _categoryController.text = location.item.category;
      _descriptionController.text = location.item.shortDescription;

      setState(() {
        _location = location;
        _containers = containers;
        _containerPathById = pathMap;
        _selectedContainerId = location.item.containerId;
        _quantity = location.item.quantity;
        _initialName = location.item.name.trim();
        _initialCategory = location.item.category.trim();
        _initialDescription = location.item.shortDescription.trim();
        _initialContainerId = location.item.containerId;
        _initialQuantity = location.item.quantity;
        _nameError = null;
        _categoryError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Impossibile caricare l\'oggetto. Verifica la connessione e riprova.';
      });
    }
  }

  Future<Map<int, String>> _buildContainerPaths(
    List<models.Container> containers,
  ) async {
    final Map<int, String> paths = <int, String>{};
    try {
      final List<House> houses = await _storage.getHouses();
      final Map<int, String> roomLabels = <int, String>{};
      for (final House house in houses) {
        final int? houseId = house.id;
        if (houseId == null) continue;
        final List<Room> rooms = await _storage.getRooms(houseId);
        for (final Room room in rooms) {
          final int? roomId = room.id;
          if (roomId != null) {
            roomLabels[roomId] = '${house.name} › ${room.name}';
          }
        }
      }
      for (final models.Container container in containers) {
        final int? id = container.id;
        if (id == null) continue;
        final String? prefix = roomLabels[container.roomId];
        paths[id] = prefix != null
            ? '$prefix · ${container.name} (${container.type.toValue()})'
            : '${container.name} (${container.type.toValue()})';
      }
    } catch (_) {
      // Optional disambiguation lookup.
    }
    return paths;
  }

  Future<void> _save() async {
    final ItemLocation? current = _location;
    final int? containerId = _selectedContainerId;
    if (current == null || containerId == null) return;

    final String name = _nameController.text.trim();
    final String category = _categoryController.text.trim();
    final String description = _descriptionController.text.trim();

    if (name.isEmpty || category.isEmpty) {
      setState(() {
        _nameError = name.isEmpty ? 'Inserisci il nome dell\'oggetto.' : null;
        _categoryError = category.isEmpty ? 'Inserisci la categoria.' : null;
      });
      return;
    }

    setState(() => _isSaving = true);
    try {
      final Item updated = current.item.copyWith(
        name: name,
        category: category,
        shortDescription: description,
        containerId: containerId,
        quantity: _quantity,
      );
      await _storage.updateItem(updated);
      if (!mounted) return;
      _showMessage('Modifiche salvate.');
      await _loadItem();
    } catch (_) {
      if (mounted) {
        _showMessage('Impossibile salvare le modifiche. Riprova.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    final ItemLocation? current = _location;
    final int? id = current?.item.id;
    if (current == null || id == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Elimina oggetto'),
          content: Text(
            'Vuoi eliminare "${current.item.name}" dall\'inventario?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _storage.deleteItem(id);
      if (!mounted) return;
      _showMessage('Oggetto eliminato.');
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/inventory?containerId=${current.item.containerId}');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Impossibile eliminare l\'oggetto.');
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop || !_isDirty || _isSaving) return;
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Modifiche non salvate'),
          content: const Text(
            'Hai apportato modifiche non salvate. Vuoi uscire comunque?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Resta'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Esci senza salvare'),
            ),
          ],
        );
      },
    );
    if (discard == true && mounted) {
      setState(() {
        _initialName = _nameController.text.trim();
        _initialCategory = _categoryController.text.trim();
        _initialDescription = _descriptionController.text.trim();
        _initialContainerId = _selectedContainerId;
        _initialQuantity = _quantity;
      });
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/inventory?containerId=${_location!.item.containerId}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty || _isSaving,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dettaglio oggetto'),
          actions: <Widget>[
            if (_location != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Elimina oggetto',
                onPressed: _isSaving ? null : _confirmAndDelete,
              ),
          ],
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
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _loadItem,
                              child: const Text('Riprova'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: <Widget>[
                            if (_location != null)
                              Card(
                                child: ListTile(
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(_location!.pathLabel),
                                  subtitle: Text(
                                    'Tipo: ${_location!.containerType.toValue()}',
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nameController,
                              onChanged: (_) {
                                if (_nameError != null) {
                                  setState(() => _nameError = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Nome oggetto',
                                errorText: _nameError,
                              ),
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _categoryController,
                              onChanged: (_) {
                                if (_categoryError != null) {
                                  setState(() => _categoryError = null);
                                } else {
                                  setState(() {});
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Categoria',
                                errorText: _categoryError,
                              ),
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _descriptionController,
                              onChanged: (_) => setState(() {}),
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Descrizione breve',
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_containers.isNotEmpty)
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: _containers.any(
                                  (models.Container c) =>
                                      c.id == _selectedContainerId,
                                )
                                    ? _selectedContainerId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Contenitore (sposta oggetto)',
                                ),
                                items: _containers
                                    .where((models.Container c) => c.id != null)
                                    .map(
                                      (models.Container c) =>
                                          DropdownMenuItem<int>(
                                        value: c.id,
                                        child: Text(
                                          _containerPathById[c.id] ??
                                              '${c.name} (${c.type.toValue()})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (int? value) {
                                  if (value != null) {
                                    setState(
                                      () => _selectedContainerId = value,
                                    );
                                  }
                                },
                              ),
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    Text(
                                      'Quantità',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton.outlined(
                                          tooltip: 'Diminuisci quantità',
                                          onPressed: _quantity > 1 && !_isSaving
                                              ? () =>
                                                  setState(() => _quantity--)
                                              : null,
                                          icon: const Icon(Icons.remove),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Semantics(
                                            liveRegion: true,
                                            label: 'Quantità: $_quantity',
                                            child: ExcludeSemantics(
                                              child: Text(
                                                '$_quantity',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton.outlined(
                                          tooltip: 'Aumenta quantità',
                                          onPressed: !_isSaving
                                              ? () =>
                                                  setState(() => _quantity++)
                                              : null,
                                          icon: const Icon(Icons.add),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _isSaving ? null : _save,
                              icon: _isSaving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                _isSaving
                                    ? 'Salvataggio...'
                                    : 'Salva modifiche',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

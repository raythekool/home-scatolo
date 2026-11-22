import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/container.dart' as models;
import '../models/item.dart';
import '../models/item_location.dart';
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
  int? _selectedContainerId;
  int _quantity = 1;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

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
        _selectedContainerId = location.item.containerId;
        _quantity = location.item.quantity;
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

  Future<void> _save() async {
    final ItemLocation? current = _location;
    final int? containerId = _selectedContainerId;
    if (current == null || containerId == null) return;

    final String name = _nameController.text.trim();
    final String category = _categoryController.text.trim();
    final String description = _descriptionController.text.trim();

    if (name.isEmpty || category.isEmpty) {
      _showMessage('Inserisci almeno nome e categoria.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            decoration: const InputDecoration(
                              labelText: 'Nome oggetto',
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Categoria',
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
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
                                        '${c.name} (${c.type.toValue()})',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (int? value) {
                                if (value != null) {
                                  setState(() => _selectedContainerId = value);
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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      IconButton.outlined(
                                        tooltip: 'Diminuisci quantità',
                                        onPressed: _quantity > 1 && !_isSaving
                                            ? () => setState(() => _quantity--)
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
                                            ? () => setState(() => _quantity++)
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
                              _isSaving ? 'Salvataggio...' : 'Salva modifiche',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

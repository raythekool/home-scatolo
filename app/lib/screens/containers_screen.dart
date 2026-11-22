import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/container.dart' as models;
import '../services/storage_factory.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({
    super.key,
    required this.roomId,
    this.storageService,
  });

  final int? roomId;
  final StorageService? storageService;

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final List<models.Container> _containers = <models.Container>[];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  @override
  void didUpdateWidget(ContainersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _loadContainers();
    }
  }

  Future<void> _loadContainers() async {
    final int? roomId = widget.roomId;
    if (roomId == null) {
      setState(() {
        _containers.clear();
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final List<models.Container> containers =
          await _storage.getContainers(roomId);
      if (!mounted) return;
      setState(() {
        _containers
          ..clear()
          ..addAll(containers);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare i contenitori. Riprova.';
      });
    }
  }

  Future<void> _showAddDialog() async {
    final int? roomId = widget.roomId;
    if (roomId == null) return;
    final ({String name, models.ContainerType type})? result =
        await showDialog<({String name, models.ContainerType type})>(
      context: context,
      builder: (BuildContext ctx) => const _AddContainerDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final models.Container container = models.Container(
        name: result.name,
        type: result.type,
        roomId: roomId,
      );
      final int id = await _storage.insertContainer(container);
      if (!mounted) return;
      setState(() {
        _containers.add(container.copyWith(id: id));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile aggiungere il contenitore.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contenitori'),
        actions: const <Widget>[
          ThemeToggleButton(),
        ],
      ),
      body: widget.roomId == null
          ? const Center(child: Text('Seleziona una stanza prima.'))
          : _isLoading
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
                              onPressed: _loadContainers,
                              child: const Text('Riprova'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _containers.isEmpty
                  ? const Center(
                      child: Text('Nessun contenitore. Aggiungine uno!'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: _containers.length,
                      itemBuilder: (BuildContext context, int index) {
                        final models.Container container = _containers[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: const Icon(Icons.inventory_2_outlined),
                              ),
                              title: Text(container.name),
                              subtitle: Text(container.type.toValue()),
                              trailing: IconButton.filledTonal(
                                icon:
                                    const Icon(Icons.document_scanner_outlined),
                                tooltip: 'Scansiona in ${container.name}',
                                onPressed: container.id == null
                                    ? null
                                    : () => context.go(
                                          '/capture?containerId=${container.id}',
                                        ),
                              ),
                              onTap: container.id == null
                                  ? null
                                  : () => context.go(
                                        '/inventory?containerId=${container.id}&title=${Uri.encodeComponent(container.name)}',
                                      ),
                            ),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.roomId == null ? null : _showAddDialog,
        tooltip: 'Aggiungi contenitore',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddContainerDialog extends StatefulWidget {
  const _AddContainerDialog();

  @override
  State<_AddContainerDialog> createState() => _AddContainerDialogState();
}

class _AddContainerDialogState extends State<_AddContainerDialog> {
  final TextEditingController _nameController = TextEditingController();
  models.ContainerType _selectedType = models.ContainerType.scatolone;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, type: _selectedType));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo contenitore'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome contenitore',
              hintText: 'Es. Scatolone Cavi',
            ),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<models.ContainerType>(
            isExpanded: true,
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: models.ContainerType.values.map((models.ContainerType t) {
              return DropdownMenuItem<models.ContainerType>(
                value: t,
                child: Text(t.toValue()),
              );
            }).toList(),
            onChanged: (models.ContainerType? value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Aggiungi'),
        ),
      ],
    );
  }
}

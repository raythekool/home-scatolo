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

  static const List<models.ContainerType> _types = models.ContainerType.values;

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

  void _showAddDialog() {
    final TextEditingController nameController = TextEditingController();
    models.ContainerType selectedType = models.ContainerType.scatolone;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Nuovo contenitore'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nome contenitore',
                      hintText: 'Es. Scatolone Cavi',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<models.ContainerType>(
                    isExpanded: true,
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: _types.map((models.ContainerType t) {
                      return DropdownMenuItem<models.ContainerType>(
                        value: t,
                        child: Text(t.toValue()),
                      );
                    }).toList(),
                    onChanged: (models.ContainerType? value) {
                      if (value != null) {
                        setDialogState(() => selectedType = value);
                      }
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () async {
                    final String name = nameController.text.trim();
                    final int? roomId = widget.roomId;
                    if (name.isEmpty || roomId == null) return;
                    try {
                      final models.Container container = models.Container(
                        name: name,
                        type: selectedType,
                        roomId: roomId,
                      );
                      final int id = await _storage.insertContainer(container);
                      if (!mounted) return;
                      setState(() {
                        _containers.add(container.copyWith(id: id));
                      });
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Impossibile aggiungere il contenitore.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Aggiungi'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(nameController.dispose);
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

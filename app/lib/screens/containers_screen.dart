import 'package:flutter/material.dart';

import '../models/container.dart' as models;
import '../services/storage_service.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({
    super.key,
    required this.roomId,
  });

  final int? roomId;

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  final StorageService _storage = StorageService();
  final List<models.Container> _containers = <models.Container>[];
  bool _isLoading = true;

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
      });
      return;
    }
    final List<models.Container> containers =
        await _storage.getContainers(roomId);
    if (!mounted) return;
    setState(() {
      _containers
        ..clear()
        ..addAll(containers);
      _isLoading = false;
    });
  }

  void _showAddDialog() {
    final TextEditingController nameController = TextEditingController();
    models.ContainerType selectedType = models.ContainerType.scatolone;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Nuovo contenitore'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Nome'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<models.ContainerType>(
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
                 },
                  child: const Text('Aggiungi'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contenitori'),
      ),
      body: widget.roomId == null
          ? const Center(child: Text('Seleziona una stanza prima.'))
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _containers.isEmpty
          ? const Center(
              child: Text('Nessun contenitore. Aggiungine uno!'))
          : ListView.builder(
              itemCount: _containers.length,
              itemBuilder: (BuildContext context, int index) {
                final models.Container container = _containers[index];
                return ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: Text(container.name),
                  subtitle: Text(container.type.toValue()),
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

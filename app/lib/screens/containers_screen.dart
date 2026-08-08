import 'package:flutter/material.dart';

import '../models/container.dart' as models;

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends State<ContainersScreen> {
  final List<models.Container> _containers = <models.Container>[];

  static const List<models.ContainerType> _types = models.ContainerType.values;

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
                    value: selectedType,
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
                  onPressed: () {
                    final String name = nameController.text.trim();
                    if (name.isEmpty) return;
                    setState(() {
                      _containers.add(models.Container(
                        id: _containers.length + 1,
                        name: name,
                        type: selectedType,
                        roomId: 0,
                      ));
                    });
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
      body: _containers.isEmpty
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
        onPressed: _showAddDialog,
        tooltip: 'Aggiungi contenitore',
        child: const Icon(Icons.add),
      ),
    );
  }
}

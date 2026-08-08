import 'package:flutter/material.dart';

import '../models/house.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key});

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> {
  final List<House> _houses = <House>[];
  int? _activeHouseId;

  void _showAddDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Nuova casa'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nome casa'),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(ctx, controller),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => _submit(ctx, controller),
              child: const Text('Aggiungi'),
            ),
          ],
        );
      },
    );
  }

  void _submit(BuildContext ctx, TextEditingController controller) {
    final String name = controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      final House house = House(
        id: _houses.length + 1,
        name: name,
      );
      _houses.add(house);
      _activeHouseId ??= house.id;
    });
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case'),
      ),
      body: _houses.isEmpty
          ? const Center(child: Text('Nessuna casa. Aggiungine una!'))
          : ListView.builder(
              itemCount: _houses.length,
              itemBuilder: (BuildContext context, int index) {
                final House house = _houses[index];
                final bool isActive = house.id == _activeHouseId;
                return ListTile(
                  leading: Icon(
                    Icons.home,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(house.name),
                  trailing: isActive
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => setState(() => _activeHouseId = house.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Aggiungi casa',
        child: const Icon(Icons.add),
      ),
    );
  }
}

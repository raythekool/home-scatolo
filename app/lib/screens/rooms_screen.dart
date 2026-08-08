import 'package:flutter/material.dart';

import '../models/room.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final List<Room> _rooms = <Room>[];

  void _showAddDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Nuova stanza'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nome stanza'),
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
      _rooms.add(Room(id: _rooms.length + 1, name: name, houseId: 0));
    });
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stanze'),
      ),
      body: _rooms.isEmpty
          ? const Center(child: Text('Nessuna stanza. Aggiungine una!'))
          : ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (BuildContext context, int index) {
                final Room room = _rooms[index];
                return ListTile(
                  leading: const Icon(Icons.room),
                  title: Text(room.name),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Aggiungi stanza',
        child: const Icon(Icons.add),
      ),
    );
  }
}

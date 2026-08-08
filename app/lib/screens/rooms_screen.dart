import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/room.dart';
import '../services/storage_service.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    required this.houseId,
  });

  final int? houseId;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final StorageService _storage = StorageService();
  final List<Room> _rooms = <Room>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void didUpdateWidget(RoomsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.houseId != widget.houseId) {
      _loadRooms();
    }
  }

  Future<void> _loadRooms() async {
    final int? houseId = widget.houseId;
    if (houseId == null) {
      setState(() {
        _rooms.clear();
        _isLoading = false;
      });
      return;
    }
    final List<Room> rooms = await _storage.getRooms(houseId);
    if (!mounted) return;
    setState(() {
      _rooms
        ..clear()
        ..addAll(rooms);
      _isLoading = false;
    });
  }

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

  Future<void> _submit(
    BuildContext ctx,
    TextEditingController controller,
  ) async {
    final String name = controller.text.trim();
    final int? houseId = widget.houseId;
    if (name.isEmpty || houseId == null) return;
    final Room room = Room(name: name, houseId: houseId);
    final int id = await _storage.insertRoom(room);
    if (!mounted) return;
    setState(() {
      _rooms.add(room.copyWith(id: id));
    });
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stanze'),
      ),
      body: widget.houseId == null
          ? const Center(child: Text('Seleziona una casa prima.'))
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
          ? const Center(child: Text('Nessuna stanza. Aggiungine una!'))
          : ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (BuildContext context, int index) {
                final Room room = _rooms[index];
                return ListTile(
                  leading: const Icon(Icons.room),
                  title: Text(room.name),
                  onTap: () {
                    final int? id = room.id;
                    if (id != null) {
                      context.go('/containers?roomId=$id');
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.houseId == null ? null : _showAddDialog,
        tooltip: 'Aggiungi stanza',
        child: const Icon(Icons.add),
      ),
    );
  }
}

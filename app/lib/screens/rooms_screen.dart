import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/room.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({
    super.key,
    required this.houseId,
    this.storageService,
  });

  final int? houseId;
  final StorageService? storageService;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final List<Room> _rooms = <Room>[];
  bool _isLoading = true;
  String? _errorMessage;

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
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final List<Room> rooms = await _storage.getRooms(houseId);
      if (!mounted) return;
      setState(() {
        _rooms
          ..clear()
          ..addAll(rooms);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare le stanze. Riprova.';
      });
    }
  }

  Future<void> _showAddDialog() async {
    final int? houseId = widget.houseId;
    if (houseId == null) return;
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => const _AddRoomDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final Room room = Room(name: name, houseId: houseId);
      final int id = await _storage.insertRoom(room);
      if (!mounted) return;
      setState(() {
        _rooms.add(room.copyWith(id: id));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aggiungere la stanza.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stanze'),
        actions: const <Widget>[
          ThemeToggleButton(),
        ],
      ),
      body: widget.houseId == null
          ? const Center(child: Text('Seleziona una casa prima.'))
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
                      onPressed: _loadRooms,
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            )
          : _rooms.isEmpty
          ? const Center(child: Text('Nessuna stanza. Aggiungine una!'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
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

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog();

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuova stanza'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nome stanza',
          hintText: 'Es. Cantina',
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _submit(),
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

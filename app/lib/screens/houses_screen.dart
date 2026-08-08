import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/house.dart';
import '../services/storage_service.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key, this.storageService});

  /// Allows injecting a fake/in-memory service in tests to avoid hitting a
  /// real database.
  final StorageService? storageService;

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> {
  late final StorageService _storage = widget.storageService ?? StorageService();
  final List<House> _houses = <House>[];
  int? _activeHouseId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHouses();
  }

  Future<void> _loadHouses() async {
    final List<House> houses = await _storage.getHouses();
    final int? activeHouseId = await _storage.getActiveHouseId();
    if (!mounted) return;
    setState(() {
      _houses
        ..clear()
        ..addAll(houses);
      _activeHouseId = houses.any((House house) => house.id == activeHouseId)
          ? activeHouseId
          : houses.isEmpty
              ? null
              : houses.first.id;
      _isLoading = false;
    });
  }

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

  Future<void> _submit(
    BuildContext ctx,
    TextEditingController controller,
  ) async {
    final String name = controller.text.trim();
    if (name.isEmpty) return;
    final House house = House(name: name);
    final int id = await _storage.insertHouse(house);
    await _storage.setActiveHouseId(id);
    if (!mounted) return;
    setState(() {
      _houses.add(house.copyWith(id: id));
      _activeHouseId = id;
    });
    if (!ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  Future<void> _selectHouse(House house) async {
    final int? id = house.id;
    if (id == null) return;
    await _storage.setActiveHouseId(id);
    if (!mounted) return;
    setState(() => _activeHouseId = id);
    context.go('/rooms?houseId=$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _houses.isEmpty
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
                  onTap: () => _selectHouse(house),
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

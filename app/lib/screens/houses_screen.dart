import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../models/house.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class HousesScreen extends StatefulWidget {
  const HousesScreen({super.key, this.storageService});

  /// Allows injecting a fake/in-memory service in tests to avoid hitting a
  /// real database.
  final StorageService? storageService;

  @override
  State<HousesScreen> createState() => _HousesScreenState();
}

class _HousesScreenState extends State<HousesScreen> {
  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final List<House> _houses = <House>[];
  int? _activeHouseId;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHouses();
  }

  Future<void> _loadHouses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossibile caricare le case. Verifica la connessione.';
      });
    }
  }

  Future<void> _showAddDialog() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => const _AddHouseDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final House house = House(name: name);
      final int id = await _storage.insertHouse(house);
      await _storage.setActiveHouseId(id);
      if (!mounted) return;
      setState(() {
        _houses.add(house.copyWith(id: id));
        _activeHouseId = id;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aggiungere la casa.')),
      );
    }
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
        actions: <Widget>[
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cerca nell\'inventario',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: _isLoading
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
                          onPressed: _loadHouses,
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                )
              : _houses.isEmpty
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Inizia dal primo oggetto',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Puoi configurare gli spazi dopo la prima scansione.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.go('/capture'),
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Scansiona subito'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _showAddDialog,
                            icon: const Icon(Icons.add_home_outlined),
                            label: const Text('Crea una casa'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHouses,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _houses.length,
                    itemBuilder: (BuildContext context, int index) {
                      final House house = _houses[index];
                      final bool isActive = house.id == _activeHouseId;
                      final ColorScheme colors = Theme.of(context).colorScheme;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isActive ? colors.primary : colors.outline,
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            selected: isActive,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerHigh,
                              child: Icon(
                                Icons.home_outlined,
                                color: colors.primary,
                              ),
                            ),
                            title: Text(house.name),
                            subtitle: Text(
                              isActive ? 'Spazio attivo' : 'Tocca per aprire',
                            ),
                            trailing: Icon(
                              isActive
                                  ? Icons.check_circle
                                  : Icons.chevron_right,
                              color: isActive
                                  ? AppTheme.successColor(context)
                                  : null,
                            ),
                            onTap: () => _selectHouse(house),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Aggiungi casa',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AddHouseDialog extends StatefulWidget {
  const _AddHouseDialog();

  @override
  State<_AddHouseDialog> createState() => _AddHouseDialogState();
}

class _AddHouseDialogState extends State<_AddHouseDialog> {
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
      title: const Text('Nuova casa'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Nome casa',
          hintText: 'Es. Casa Vaiano',
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

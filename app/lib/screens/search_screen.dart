import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/storage_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final StorageService _storage = StorageService();
  final TextEditingController _controller = TextEditingController();
  final List<Item> _results = <Item>[];
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    final List<Item> results = await _storage.searchItems(query);
    if (!mounted) return;
    setState(() {
      _results
        ..clear()
        ..addAll(results);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ricerca'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Cerca...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const LinearProgressIndicator()
            else if (_controller.text.trim().isEmpty)
              const Text('Inserisci un testo per cercare.')
            else if (_results.isEmpty)
              const Text('Nessun risultato.')
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Item item = _results[index];
                    return ListTile(
                      leading: const Icon(Icons.inventory),
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.category} · ${item.shortDescription}',
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/item_location.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.storageService});

  final StorageService? storageService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _debounceDuration = Duration(milliseconds: 280);

  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final TextEditingController _controller = TextEditingController();
  final List<ItemLocation> _results = <ItemLocation>[];
  Timer? _debounce;
  int _requestSeq = 0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _requestSeq++;
      setState(() {
        _results.clear();
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    _debounce = Timer(_debounceDuration, () => _executeSearch(query));
  }

  Future<void> _executeSearch(String query) async {
    final int seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<ItemLocation> results =
          await _storage.searchItemsWithLocation(query);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results
          ..clear()
          ..addAll(results);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Ricerca non disponibile. Verifica la connessione e riprova.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ricerca inventario'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Cerca un oggetto',
                hintText: 'Es. cavo HDMI, trapano, cantina...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: _executeSearch,
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const LinearProgressIndicator()
            else if (_errorMessage != null)
              Column(
                children: <Widget>[
                  Text(_errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _executeSearch(_controller.text),
                    child: const Text('Riprova'),
                  ),
                ],
              )
            else if (_controller.text.trim().isEmpty)
              const Text('Inserisci un testo per cercare dove hai messo un oggetto.')
            else if (_results.isEmpty)
              Semantics(
                liveRegion: true,
                child: const Text('Nessun risultato trovato.'),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final ItemLocation match = _results[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(match.item.name),
                        subtitle: Text(
                          '${match.pathLabel}\n${match.item.category}'
                          '${match.item.shortDescription.isNotEmpty ? ' · ${match.item.shortDescription}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          'x${match.item.quantity}',
                          semanticsLabel: 'Quantità ${match.item.quantity}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        onTap: match.item.id == null
                            ? null
                            : () async {
                                await context.push('/items/${match.item.id}');
                                if (mounted &&
                                    _controller.text.trim().isNotEmpty) {
                                  _executeSearch(_controller.text);
                                }
                              },
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

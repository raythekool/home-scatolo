import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ricerca inventario'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Cerca un oggetto',
                      hintText: 'Es. cavo HDMI, trapano, cantina...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Pulisci ricerca',
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                            )
                          : null,
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
                  else if (!hasQuery)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.search_outlined,
                              size: 48,
                              color: colors.primary,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Inserisci un testo per cercare dove hai messo un oggetto.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: <String>[
                                'Elettronica',
                                'Cavi',
                                'Attrezzi',
                                'Documenti',
                              ]
                                  .map(
                                    (String term) => ActionChip(
                                      label: Text(term),
                                      onPressed: () {
                                        _controller.text = term;
                                        _controller.selection =
                                            TextSelection.collapsed(
                                          offset: term.length,
                                        );
                                        _executeSearch(term);
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_results.isEmpty)
                    Semantics(
                      liveRegion: true,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Nessun risultato trovato.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else ...<Widget>[
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _results.length == 1
                              ? '1 risultato trovato'
                              : '${_results.length} risultati trovati',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final ItemLocation match = _results[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colors.primaryContainer,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: colors.onPrimaryContainer,
                                ),
                              ),
                              title: Text(match.item.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: <Widget>[
                                      Icon(
                                        Icons.place_outlined,
                                        size: 14,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          match.pathLabel,
                                          style: TextStyle(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${match.item.category}'
                                    '${match.item.shortDescription.isNotEmpty ? ' · ${match.item.shortDescription}' : ''}',
                                  ),
                                ],
                              ),
                              trailing: Container(
                                constraints: const BoxConstraints(minWidth: 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'x${match.item.quantity}',
                                  semanticsLabel:
                                      'Quantità ${match.item.quantity}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              onTap: match.item.id == null
                                  ? null
                                  : () async {
                                      await context.push(
                                        '/items/${match.item.id}',
                                      );
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

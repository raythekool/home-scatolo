import 'dart:convert';
import 'dart:typed_data';

import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../models/container.dart' as models;
import '../models/item.dart';
import '../models/recognition_candidate.dart';
import '../services/api_client.dart';
import '../services/camera_service.dart';
import '../services/duplicate_matcher.dart';
import '../services/storage_factory.dart';
import '../services/storage_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.containerId, this.storageService});

  final int? containerId;
  final StorageService? storageService;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  static const int _maxImageBytes = 5 * 1024 * 1024;

  final CameraService _cameraService = CameraService();
  late final StorageService _storage =
      widget.storageService ?? createStorageService();
  final ApiClient _apiClient = ApiClient();
  final DuplicateMatcher _duplicateMatcher = const DuplicateMatcher();
  XFile? _selectedFile;
  Uint8List? _imageBytes;
  List<RecognitionDecision> _decisions = <RecognitionDecision>[];
  List<RecognitionAction> _selectedActions = <RecognitionAction>[];
  List<int> _quantities = <int>[];
  bool _isRecognizing = false;
  bool _isSaving = false;
  bool _isPreparing = true;
  String? _prepareError;
  _BackendStatus _backendStatus = _BackendStatus.checking;
  int? _resolvedContainerId;
  String? _containerLabel;

  @override
  void initState() {
    super.initState();
    _prepareDestination();
    _checkBackend();
  }

  Future<void> _prepareDestination() async {
    setState(() {
      _isPreparing = true;
      _prepareError = null;
    });
    try {
      final int containerId =
          widget.containerId ?? await _storage.getOrCreateQuickScanContainer();
      String? containerLabel;
      try {
        final List<models.Container> all = await _storage.getAllContainers();
        for (final models.Container c in all) {
          if (c.id == containerId) {
            containerLabel = '${c.name} (${c.type.toValue()})';
            break;
          }
        }
      } catch (_) {
        // Optional container label lookup.
      }
      if (!mounted) return;
      setState(() {
        _resolvedContainerId = containerId;
        _containerLabel = containerLabel;
        _isPreparing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _prepareError =
            'Impossibile preparare il contenitore di destinazione.';
      });
    }
  }

  Future<void> _checkBackend() async {
    if (mounted) setState(() => _backendStatus = _BackendStatus.checking);
    final bool isAvailable = await _apiClient.healthCheck();
    if (!mounted) return;
    setState(
      () => _backendStatus =
          isAvailable ? _BackendStatus.ready : _BackendStatus.unavailable,
    );
  }

  Future<void> _pick(Future<XFile?> Function() picker) async {
    final XFile? file = await picker();
    if (file == null) return;

    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.lengthInBytes > _maxImageBytes) {
      _showMessage("Scegli un'immagine inferiore a 5 MB.");
      return;
    }

    setState(() {
      _selectedFile = file;
      _imageBytes = bytes;
      _decisions = <RecognitionDecision>[];
      _selectedActions = <RecognitionAction>[];
      _quantities = <int>[];
    });
  }

  Future<void> _recognize() async {
    final int? containerId = _resolvedContainerId;
    final XFile? file = _selectedFile;
    final Uint8List? imageBytes = _imageBytes;
    if (containerId == null || file == null || imageBytes == null) return;

    final String mimeType = file.mimeType ?? 'image/jpeg';
    if (!<String>{'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
      _showMessage("Il formato dell'immagine non è supportato.");
      return;
    }

    setState(() => _isRecognizing = true);
    try {
      final List<Item> existingItems = await _storage.getItems(containerId);
      final List<RecognitionCandidate> candidates = await _apiClient.recognize(
        imageBase64: base64Encode(imageBytes),
        mimeType: mimeType,
        existingItems: existingItems,
      );
      if (!mounted) return;
      final List<RecognitionDecision> decisions = candidates
          .map(
            (RecognitionCandidate candidate) => _duplicateMatcher.decide(
              candidate: candidate,
              containerItems: existingItems,
            ),
          )
          .toList();
      setState(() {
        _decisions = decisions;
        _selectedActions = decisions
            .map((RecognitionDecision decision) => decision.action)
            .toList();
        _quantities = decisions
            .map((RecognitionDecision decision) => decision.candidate.quantity)
            .toList();
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
            'Riconoscimento non disponibile. Controlla il backend e riprova.');
      }
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  Future<void> _saveConfirmed() async {
    final int? containerId = _resolvedContainerId;
    if (containerId == null) return;
    if (_selectedActions.contains(RecognitionAction.review)) {
      _showMessage("Scegli un'azione per ogni elemento da verificare.");
      return;
    }

    setState(() => _isSaving = true);
    try {
      for (int index = 0; index < _decisions.length; index++) {
        final RecognitionDecision decision = _decisions[index];
        final RecognitionAction action = _selectedActions[index];
        final int quantity = _quantities[index];
        if (action == RecognitionAction.ignore) continue;
        if (action == RecognitionAction.mergeQuantity &&
            decision.matchedItem != null) {
          await _storage.incrementItemQuantity(
            itemId: decision.matchedItem!,
            amount: quantity,
          );
          continue;
        }
        await _storage.insertItem(
          Item(
            name: decision.candidate.name,
            category: decision.candidate.category,
            shortDescription: decision.candidate.shortDescription,
            containerId: containerId,
            insertedAt: DateTime.now(),
            quantity: quantity,
          ),
        );
      }
      if (!mounted) return;
      _showMessage('Inventario aggiornato.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/inventory?containerId=$containerId');
      }
    } catch (_) {
      if (mounted) _showMessage('Non è stato possibile salvare le modifiche.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = _imageBytes != null;
    final bool canRecognize = hasImage &&
        _resolvedContainerId != null &&
        !_isRecognizing &&
        _backendStatus == _BackendStatus.ready;
    final bool canSave = _decisions.isNotEmpty && !_isSaving;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuova scansione')),
      body: SafeArea(
        child: _isPreparing
            ? const Center(child: CircularProgressIndicator())
            : _prepareError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(_prepareError!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _prepareDestination,
                            child: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  )
                : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          constraints.maxWidth > 600 ? 24 : 16,
                          16,
                          constraints.maxWidth > 600 ? 24 : 16,
                          32,
                        ),
                        children: <Widget>[
                          _buildScanHeader(context),
                          const SizedBox(height: 12),
                          _buildBackendStatus(context),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _isRecognizing
                                ? null
                                : () =>
                                    _pick(_cameraService.pickImageFromCamera),
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Scatta foto'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isRecognizing
                                ? null
                                : () =>
                                    _pick(_cameraService.pickImageFromGallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Scegli dalla galleria'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                            ),
                          ),
                          if (hasImage) ...<Widget>[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.cover,
                                  semanticLabel:
                                      'Anteprima della foto selezionata per la scansione',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: canRecognize ? _recognize : null,
                              icon: _isRecognizing ||
                                      _backendStatus == _BackendStatus.checking
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.auto_awesome),
                              label: Text(_isRecognizing
                                  ? 'Riconoscimento...'
                                  : _backendStatus == _BackendStatus.checking
                                      ? 'Preparo il riconoscimento...'
                                      : 'Analizza foto'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(58),
                              ),
                            ),
                            if (_isRecognizing) ...<Widget>[
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  'Analisi AI in corso: se il provider cloud non risponde interviene Ollama locale (~15–40s).',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                          if (_decisions.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 24),
                            const Text('Rivedi prima di salvare'),
                            const SizedBox(height: 8),
                            ...List<Widget>.generate(
                                _decisions.length, _buildDecision),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: canSave ? _saveConfirmed : null,
                              icon: _isSaving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(_isSaving
                                  ? 'Salvataggio...'
                                  : 'Conferma modifiche'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(58),
                              ),
                            ),
                            if (_isRecognizing) ...<Widget>[
                              const SizedBox(height: 8),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  'Analisi AI in corso: se il provider cloud non risponde interviene Ollama locale (~15–40s).',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildScanHeader(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 25,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            child: const Icon(Icons.document_scanner_outlined),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cosa c\'è qui?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _containerLabel != null
                      ? 'Destinazione: $_containerLabel'
                      : 'Scatta una foto o selezionala dalla galleria.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendStatus(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget content = switch (_backendStatus) {
      _BackendStatus.ready => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Riconoscimento pronto')),
            ],
          ),
        ),
      _BackendStatus.checking => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Verifica disponibilità riconoscimento',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sto preparando il riconoscimento. Dopo una pausa può richiedere fino a un minuto.',
                ),
              ),
            ],
          ),
        ),
      _BackendStatus.unavailable => Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.cloud_off_outlined, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Il riconoscimento non è disponibile.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: _checkBackend,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
    };
    return Semantics(container: true, liveRegion: true, child: content);
  }

  Widget _buildDecision(int index) {
    final RecognitionDecision decision = _decisions[index];
    final RecognitionCandidate candidate = decision.candidate;
    final RecognitionAction currentAction = _selectedActions[index];
    final int currentQuantity = _quantities[index];
    final bool hasMatch = decision.matchedItem != null;
    final List<RecognitionAction> availableActions = <RecognitionAction>[
      RecognitionAction.add,
      if (hasMatch) RecognitionAction.mergeQuantity,
      RecognitionAction.ignore,
    ];
    final Set<RecognitionAction> selectedSet =
        availableActions.contains(currentAction)
            ? <RecognitionAction>{currentAction}
            : const <RecognitionAction>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          candidate.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          candidate.category,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton.outlined(
                        tooltip: 'Diminuisci quantità per ${candidate.name}',
                        onPressed: !_isSaving && currentQuantity > 1
                            ? () => setState(() => _quantities[index]--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'x$currentQuantity',
                          semanticsLabel: 'Quantità $currentQuantity',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Aumenta quantità per ${candidate.name}',
                        onPressed: !_isSaving
                            ? () => setState(() => _quantities[index]++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
              if (candidate.shortDescription.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(candidate.shortDescription),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RecognitionAction>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: availableActions
                      .map(
                        (RecognitionAction action) =>
                            ButtonSegment<RecognitionAction>(
                          value: action,
                          label: Text(_shortActionLabel(action)),
                          tooltip: _actionLabel(action),
                        ),
                      )
                      .toList(),
                  selected: selectedSet,
                  onSelectionChanged: _isSaving
                      ? null
                      : (Set<RecognitionAction> selection) {
                          if (selection.isEmpty) return;
                          setState(
                            () => _selectedActions[index] = selection.first,
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortActionLabel(RecognitionAction action) {
    return switch (action) {
      RecognitionAction.add => 'Nuovo',
      RecognitionAction.mergeQuantity => 'Somma (+)',
      RecognitionAction.review => 'Verifica',
      RecognitionAction.ignore => 'Ignora',
    };
  }

  String _actionLabel(RecognitionAction action) {
    return switch (action) {
      RecognitionAction.add => 'Aggiungi come nuovo',
      RecognitionAction.mergeQuantity => 'Incrementa quantità esistente',
      RecognitionAction.review => 'Da verificare',
      RecognitionAction.ignore => 'Ignora',
    };
  }
}

enum _BackendStatus { checking, ready, unavailable }

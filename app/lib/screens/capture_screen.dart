import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/item.dart';
import '../models/recognition_candidate.dart';
import '../services/api_client.dart';
import '../services/camera_service.dart';
import '../services/duplicate_matcher.dart';
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
      widget.storageService ?? StorageService();
  final ApiClient _apiClient = ApiClient();
  final DuplicateMatcher _duplicateMatcher = const DuplicateMatcher();
  XFile? _selectedFile;
  Uint8List? _imageBytes;
  List<RecognitionDecision> _decisions = <RecognitionDecision>[];
  List<RecognitionAction> _selectedActions = <RecognitionAction>[];
  bool _isRecognizing = false;
  bool _isSaving = false;
  bool _isPreparing = true;
  _BackendStatus _backendStatus = _BackendStatus.checking;
  int? _resolvedContainerId;

  @override
  void initState() {
    super.initState();
    _prepareDestination();
    _checkBackend();
  }

  Future<void> _prepareDestination() async {
    final int containerId =
        widget.containerId ?? await _storage.getOrCreateQuickScanContainer();
    if (!mounted) return;
    setState(() {
      _resolvedContainerId = containerId;
      _isPreparing = false;
    });
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
        if (action == RecognitionAction.ignore) continue;
        if (action == RecognitionAction.mergeQuantity &&
            decision.matchedItem != null) {
          await _storage.incrementItemQuantity(
            itemId: decision.matchedItem!,
            amount: decision.candidate.quantity,
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
            quantity: decision.candidate.quantity,
          ),
        );
      }
      if (!mounted) return;
      _showMessage('Inventario aggiornato.');
      Navigator.of(context).pop();
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
                                child: Image.memory(_imageBytes!,
                                    fit: BoxFit.cover),
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
                const Text('Scatta una foto o selezionala dalla galleria.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendStatus(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return switch (_backendStatus) {
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
              Text('Riconoscimento pronto'),
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
                child: CircularProgressIndicator(strokeWidth: 2),
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
  }

  Widget _buildDecision(int index) {
    final RecognitionDecision decision = _decisions[index];
    final RecognitionCandidate candidate = decision.candidate;
    final List<RecognitionAction> actions = <RecognitionAction>[
      RecognitionAction.add,
      if (decision.matchedItem != null) RecognitionAction.mergeQuantity,
      RecognitionAction.ignore,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(candidate.name,
                style: Theme.of(context).textTheme.titleMedium),
            Text('${candidate.category} · Quantità ${candidate.quantity}'),
            Text(candidate.shortDescription),
            const SizedBox(height: 8),
            DropdownButtonFormField<RecognitionAction>(
              initialValue: actions.contains(_selectedActions[index])
                  ? _selectedActions[index]
                  : null,
              decoration: const InputDecoration(labelText: 'Azione'),
              hint: const Text('Scegli cosa fare'),
              items: actions
                  .map(
                    (RecognitionAction action) =>
                        DropdownMenuItem<RecognitionAction>(
                      value: action,
                      child: Text(_actionLabel(action)),
                    ),
                  )
                  .toList(),
              onChanged: (RecognitionAction? action) {
                if (action == null) return;
                setState(() => _selectedActions[index] = action);
              },
            ),
          ],
        ),
      ),
    );
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

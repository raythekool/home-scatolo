import 'package:flutter/material.dart';

import '../services/camera_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final CameraService _cameraService = CameraService();
  String? _selectedPath;
  String? _selectedType;

  Future<void> _pick(String type, Future<String?> Function() picker) async {
    final String? path = await picker();
    if (!mounted || path == null) return;
    setState(() {
      _selectedType = type;
      _selectedPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cattura'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => _pick(
                'Foto da camera',
                _cameraService.pickImageFromCamera,
              ),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Scatta foto'),
            ),
            FilledButton.icon(
              onPressed: () => _pick(
                'Foto da galleria',
                _cameraService.pickImageFromGallery,
              ),
              icon: const Icon(Icons.photo_library),
              label: const Text('Scegli foto'),
            ),
            FilledButton.icon(
              onPressed: () => _pick(
                'Video da camera',
                _cameraService.pickVideoFromCamera,
              ),
              icon: const Icon(Icons.videocam),
              label: const Text('Registra video'),
            ),
            FilledButton.icon(
              onPressed: () => _pick(
                'Video da galleria',
                _cameraService.pickVideoFromGallery,
              ),
              icon: const Icon(Icons.video_library),
              label: const Text('Scegli video'),
            ),
            const SizedBox(height: 24),
            if (_selectedPath == null)
              const Text('Nessun file selezionato.')
            else
              Text('$_selectedType: $_selectedPath'),
          ],
        ),
      ),
    );
  }
}

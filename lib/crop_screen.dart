import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Pantalla de recorte simple: el usuario hace pan/zoom sobre la imagen
/// dentro de un marco cuadrado fijo, y al confirmar capturamos
/// exactamente lo que se ve dentro de ese marco. No usa ningún paquete
/// externo: todo es InteractiveViewer + RepaintBoundary, parte del SDK
/// de Flutter.
class CropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const CropScreen({super.key, required this.imageBytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _capturing = false;

  static const double _frameSize = 300;

  Future<void> _confirm() async {
    setState(() => _capturing = true);
    try {
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;
      final image = await renderObject.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      if (mounted) Navigator.pop(context, pngBytes);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustar sticker'),
        actions: [
          IconButton(
            icon: _capturing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check),
            onPressed: _capturing ? null : _confirm,
          ),
        ],
      ),
      backgroundColor: Colors.black87,
      body: Center(
        child: RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            width: _frameSize,
            height: _frameSize,
            color: Colors.white,
            child: ClipRect(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black87,
        padding: const EdgeInsets.all(16),
        child: const Text(
          'Arrastra y pellizca para ajustar el encuadre. Toca ✓ para confirmar.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

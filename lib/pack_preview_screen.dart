import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mock_data.dart';

/// Vista pública de un pack: solo para ver los stickers y "descargarlo"
/// (añadirlo a WhatsApp). Sin ningún acceso de edición.
///
/// Puede mostrar un pack REAL (identifier real, se puede añadir a
/// WhatsApp de verdad) o un pack MOCK (de un creador simulado — el botón
/// de descargar muestra un aviso de que es una demo, ya que ese pack no
/// existe realmente en el dispositivo).
class PackPreviewScreen extends StatefulWidget {
  final String? realIdentifier;
  final MockPack? mockPack;
  final String displayName;

  const PackPreviewScreen({
    super.key,
    this.realIdentifier,
    this.mockPack,
    required this.displayName,
  });

  @override
  State<PackPreviewScreen> createState() => _PackPreviewScreenState();
}

class _PackPreviewScreenState extends State<PackPreviewScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Uint8List> _stickers = [];
  bool _loading = true;

  bool get _isMock => widget.realIdentifier == null;

  @override
  void initState() {
    super.initState();
    if (!_isMock) {
      _loadRealStickers();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadRealStickers() async {
    try {
      final stickers = await _channel
          .invokeListMethod<Uint8List>('getStickersForPack', {'identifier': widget.realIdentifier});
      if (mounted) setState(() => _stickers = stickers ?? []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    if (_isMock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esto es una demo — con el backend real, aquí se añadiría el pack a tu WhatsApp.'),
        ),
      );
      return;
    }
    try {
      final result = await _channel.invokeMethod<String>('addStickerPack', {
        'identifier': widget.realIdentifier,
        'name': widget.displayName,
      });
      final mensaje = switch (result) {
        'added' => 'Pack añadido ✅',
        'cancelled' => 'Cancelado',
        _ => 'Resultado: $result',
      };
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mock = widget.mockPack;

    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _isMock
                      ? _MockStickerGrid(mock: mock!)
                      : _stickers.isEmpty
                          ? const Center(child: Text('Este pack no tiene stickers'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _stickers.length,
                              itemBuilder: (context, index) => Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Image.memory(_stickers[index], fit: BoxFit.contain),
                              ),
                            ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _download,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Añadir a mi WhatsApp'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MockStickerGrid extends StatelessWidget {
  final MockPack mock;
  const _MockStickerGrid({required this.mock});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: mock.stickerCount,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: mock.previewColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(mock.previewIcon, color: mock.previewColor, size: 28),
      ),
    );
  }
}

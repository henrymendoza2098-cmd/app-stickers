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
  final String packName;
  final String? publisherName;

  const PackPreviewScreen({
    super.key,
    this.realIdentifier,
    this.mockPack,
    required this.packName,
    this.publisherName,
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
        'identifier': widget.realIdentifier!,
        'name': widget.packName,
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

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              title: Text(widget.packName),
              pinned: true,
              floating: true,
            ),
            SliverToBoxAdapter(
              child: _PackHeader(
                packName: widget.packName,
                publisherName: widget.publisherName,
                onAdd: _download,
              ),
            ),
          ],
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _isMock
                  ? _MockStickerList(mock: mock!)
                  : _stickers.isEmpty
                      ? const Center(child: Text('Este pack no tiene stickers'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _stickers.length,
                          itemBuilder: (context, index) {
                            return _StickerListTile(
                              stickerBytes: _stickers[index],
                              // TODO: Cuando guardemos emojis por sticker, pasarlos aquí
                              emojis: const ['😀'],
                            );
                          },
                        ),
        ),
      ),
    );
  }
}

class _PackHeader extends StatelessWidget {
  final String packName;
  final String? publisherName;
  final VoidCallback onAdd;

  const _PackHeader({required this.packName, this.publisherName, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(packName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (publisherName != null && publisherName!.isNotEmpty)
                  Text('de $publisherName', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            label: const Text('Añadir'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
          ),
        ],
      ),
    );
  }
}

class _StickerListTile extends StatelessWidget {
  final Uint8List stickerBytes;
  final List<String> emojis;

  const _StickerListTile({required this.stickerBytes, required this.emojis});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Image.memory(stickerBytes, fit: BoxFit.contain),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                emojis.join(' '),
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockStickerList extends StatelessWidget {
  final MockPack mock;
  const _MockStickerList({required this.mock});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: mock.stickerCount,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              SizedBox(
                  width: 72, height: 72, child: Icon(mock.previewIcon, color: mock.previewColor, size: 40)),
              const SizedBox(width: 16),
              const Expanded(child: Text('✨', style: TextStyle(fontSize: 22))),
            ],
          ),
        ),
      ),
    );
  }
}

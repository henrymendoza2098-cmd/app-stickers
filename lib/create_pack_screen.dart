import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'crop_screen.dart';
import 'page_transitions.dart';

class CreatePackScreen extends StatefulWidget {
  final String? packName;
  final String? publisher;
  final String? identifier;
  final bool isEditing;
  final List<Uint8List>? initialStickers;

  const CreatePackScreen({
    super.key,
    this.packName,
    this.publisher,
    this.identifier,
    this.isEditing = false,
    this.initialStickers,
  });

  @override
  State<CreatePackScreen> createState() => _CreatePackScreenState();
}

class _CreatePackScreenState extends State<CreatePackScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  final _nameController = TextEditingController();
  final _publisherController = TextEditingController();
  final List<Uint8List> _stickers = [];
  bool _saving = false;
  String _status = '';
  bool _loadingStickers = false;

  @override
  void initState() {
    super.initState();
    if (widget.packName != null) _nameController.text = widget.packName!;
    if (widget.publisher != null) _publisherController.text = widget.publisher!;
    if (widget.initialStickers != null) _stickers.addAll(widget.initialStickers!);
    if (widget.isEditing) _loadExistingStickers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _publisherController.dispose();
    super.dispose();
  }

  Future<void> _addSticker() async {
    final Uint8List? original = await _channel.invokeMethod<Uint8List>('pickImage');
    if (original == null || !mounted) return;

    final cropped = await Navigator.push<Uint8List>(
      context,
      slideUpRoute(CropScreen(imageBytes: original)),
    );
    if (cropped == null) return;

    setState(() => _stickers.add(cropped));
  }

  void _removeSticker(int index) {
    setState(() => _stickers.removeAt(index));
  }

  Future<void> _savePack() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _status = 'Ponle un nombre al pack');
      return;
    }
    if (_stickers.length < 3) {
      setState(() => _status = 'Necesitas al menos 3 stickers (tienes ${_stickers.length})');
      return;
    }

    setState(() {
      _saving = true;
      _status = '';
    });

    final identifier = widget.identifier ?? 'pack_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await _channel.invokeMethod('saveStickerPack', {
        'identifier': identifier,
        'name': name,
        'publisher': widget.publisher ?? _publisherController.text.trim(),
        'tray': _stickers.first,
        'stickers': _stickers
            .map((bytes) => {
                  'bytes': bytes,
                  'emojis': ['😀'],
                })
            .toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (e) {
      setState(() => _status = 'Error al guardar: ${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadExistingStickers() async {
    if (widget.identifier == null) return;
    setState(() => _loadingStickers = true);
    try {
      final List<Uint8List>? stickerBytes =
          await _channel.invokeListMethod<Uint8List>('getStickersForPack', {'identifier': widget.identifier});
      if (stickerBytes != null && mounted) {
        setState(() {
          _stickers.addAll(stickerBytes);
        });
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Error cargando stickers: ${e.message}');
    } finally {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Editar pack' : 'Crear nuevo pack')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.packName == null) ...[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre del pack'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _publisherController,
                decoration: const InputDecoration(labelText: 'Autor del pack'),
              ),
              const SizedBox(height: 18),
            ] else ...[
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: _stickers.isNotEmpty
                        ? Image.memory(_stickers.first, fit: BoxFit.contain)
                        : Icon(Icons.collections_bookmark_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.packName!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        if (widget.publisher != null && widget.publisher!.isNotEmpty)
                          Text(widget.publisher!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'Stickers (${_stickers.length}/30, mínimo 3)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loadingStickers
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _stickers.length + (_stickers.length < 30 ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _stickers.length) {
                          return InkWell(
                            onTap: _addSticker,
                            borderRadius: BorderRadius.circular(14),
                            child: DottedAddTile(color: colorScheme.primary),
                          );
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(_stickers[index], fit: BoxFit.contain),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeSticker(index),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_status, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _savePack,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar pack'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Casilla punteada para "agregar sticker", a juego con la paleta.
class DottedAddTile extends StatelessWidget {
  final Color color;
  const DottedAddTile({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Icon(Icons.add_photo_alternate_rounded, size: 28, color: color.withValues(alpha: 0.7)),
    );
  }
}

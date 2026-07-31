import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'create_pack_screen.dart';
import 'page_transitions.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Map<String, dynamic>> _packs = [];
  final Map<String, Uint8List> _trayCache = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadPacks();
  }

  Future<void> loadPacks() async {
    setState(() => _loading = true);
    try {
      final jsonStr = await _channel.invokeMethod<String>('getStickerPacks');
      final List<dynamic> list = jsonDecode(jsonStr ?? '[]');
      _packs = list.cast<Map<String, dynamic>>();

      for (final pack in _packs) {
        final id = pack['identifier'] as String;
        if (!_trayCache.containsKey(id)) {
          final bytes = await _channel.invokeMethod<Uint8List>('getPackTray', {'identifier': id});
          if (bytes != null) _trayCache[id] = bytes;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando packs: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addToWhatsApp(String identifier, String name) async {
    try {
      final result = await _channel.invokeMethod<String>('addStickerPack', {
        'identifier': identifier,
        'name': name,
      });
      final mensaje = switch (result) {
        'added' => 'Pack añadido ✅',
        'cancelled' => 'Cancelado',
        _ => 'Resultado: $result',
      };
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    }
  }

  Future<void> _deletePack(String identifier) async {
    await _channel.invokeMethod('deleteStickerPack', {'identifier': identifier});
    _trayCache.remove(identifier);
    loadPacks();
  }

  void _confirmDelete(String identifier, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar pack?'),
        content: Text('Se eliminará "$name" y todos sus stickers. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePack(identifier);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openPack(String identifier, String name, String publisher, bool isDynamic) {
    if (!isDynamic) return;
    Navigator.push<bool>(
      context,
      slideUpRoute(
        CreatePackScreen(
          packName: name,
          publisher: publisher,
          identifier: identifier,
          isEditing: true,
        ),
      ),
    ).then((updated) {
      if (updated == true) loadPacks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis stickers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _packs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 48, color: colorScheme.primary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        const Text(
                          'Todavía no tienes packs.\nCrea el primero con el botón +',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadPacks,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: _packs.length,
                    itemBuilder: (context, index) {
                      final pack = _packs[index];
                      final identifier = pack['identifier'] as String;
                      final name = pack['name'] as String;
                      final publisher = pack['publisher'] as String? ?? '';
                      final isDynamic = pack['isDynamic'] as bool? ?? false;
                      final trayBytes = _trayCache[identifier];

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openPack(identifier, name, publisher, isDynamic),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      color: colorScheme.primary.withValues(alpha: 0.08),
                                      padding: const EdgeInsets.all(18),
                                      child: trayBytes != null
                                          ? Image.memory(trayBytes, fit: BoxFit.contain)
                                          : Icon(Icons.image_rounded,
                                              size: 36, color: colorScheme.primary.withValues(alpha: 0.35)),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: _PackMenuButton(
                                        onSend: () => _addToWhatsApp(identifier, name),
                                        onDelete: isDynamic ? () => _confirmDelete(identifier, name) : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (publisher.isNotEmpty)
                                      Text(
                                        publisher,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${pack['stickerCount']} stickers',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePackSheet,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pack'),
      ),
    );
  }

  void _showCreatePackSheet() {
    final nameController = TextEditingController();
    final publisherController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Nuevo pack de stickers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre del pack')),
            const SizedBox(height: 10),
            TextField(controller: publisherController, decoration: const InputDecoration(labelText: 'Autor')),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push<bool>(
                  context,
                  slideUpRoute(
                    CreatePackScreen(packName: nameController.text, publisher: publisherController.text),
                  ),
                ).then((created) => {if (created == true) loadPacks()});
              },
              child: const Text('Crear y añadir stickers'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Menú flotante compacto (⋮) sobre cada tarjeta, para no saturar el grid
/// con varios íconos de acción.
class _PackMenuButton extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback? onDelete;

  const _PackMenuButton({required this.onSend, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (value) {
          if (value == 'send') onSend();
          if (value == 'delete') onDelete?.call();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'send',
            child: Row(children: [Icon(Icons.send_rounded, size: 18), SizedBox(width: 10), Text('Añadir a WhatsApp')]),
          ),
          if (onDelete != null)
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                SizedBox(width: 10),
                Text('Eliminar', style: TextStyle(color: Colors.red)),
              ]),
            ),
        ],
      ),
    );
  }
}

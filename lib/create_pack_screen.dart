import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'crop_screen.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'supabase_storage_service.dart';
import 'favorites_repository.dart';
import 'page_transitions.dart';

class CreatePackScreen extends StatefulWidget {
  final String? packName;
  final String? publisher;
  final String? identifier;
  final bool isEditing;
  final bool isPrivate;
  final List<Uint8List>? initialStickers;
  final List<String>? initialStickerUrls;

  const CreatePackScreen({
    super.key,
    this.packName,
    this.publisher,
    this.identifier,
    this.isEditing = false,
    this.isPrivate = true, // Los packs nuevos son privados por defecto
    this.initialStickers,
    this.initialStickerUrls,
  });

  @override
  State<CreatePackScreen> createState() => _CreatePackScreenState();
}

class _CreatePackScreenState extends State<CreatePackScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  final _nameController = TextEditingController();
  final _publisherController = TextEditingController();

  final _firestore = FirestoreService.instance;
  final _storage = SupabaseStorageService.instance;
  final _auth = AuthService.instance;
  final _favoritesRepo = FavoritesRepository();

  final List<Uint8List> _stickers = [];
  bool _saving = false;
  String _status = '';
  bool _loadingStickers = false;
  late bool _isPrivate;

  @override
  void initState() {
    super.initState();
    if (widget.packName != null) _nameController.text = widget.packName!;
    if (widget.publisher != null) _publisherController.text = widget.publisher!;
    if (widget.initialStickers != null) _stickers.addAll(widget.initialStickers!);
    _isPrivate = widget.isPrivate;
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
    final publisher = widget.publisher ?? _publisherController.text.trim();

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
    final uid = _auth.currentUid;

    // 1. Guardar localmente. Esto es lo único indispensable — si falla,
    // sí es un error real y detenemos todo aquí.
    try {
      await _channel.invokeMethod('saveStickerPack', {
        'identifier': identifier,
        'name': name,
        'publisher': publisher,
        'authorUid': uid, // Asociar el pack con el usuario actual
        'tray': _stickers.first,
        'stickers': _stickers
            .map((bytes) => {
                  'bytes': bytes,
                  'emojis': ['😀'],
                })
            .toList(),
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error al guardar: $e';
          _saving = false;
        });
      }
      return;
    }

    // 2. Si hay sesión iniciada, intentar sincronizar también con la nube.
    // IMPORTANTE: esto es un extra. El pack YA se guardó bien localmente
    // en el paso 1, así que si esto falla NO debe bloquear ni ocultar ese
    // éxito — solo avisamos con un mensaje suave y seguimos igual.
    if (!_auth.isAnonymous && _auth.currentUid != null) {
      try {
        final uploadResult = await _storage.uploadPack(
          authorUid: _auth.currentUid!,
          packId: identifier,
          trayBytes: _stickers.first,
          stickerBytes: _stickers,
        );

        await _firestore.publishPack(
            packId: identifier,
            name: name,
            authorUid: _auth.currentUid!,
            authorName: publisher,
            trayUrl: uploadResult.trayUrl,
            stickers: uploadResult.stickerUrls.map((url) => {'url': url, 'emojis': ['😀']}).toList(),
            isPublic: false, // El pack comienza como privado en la nube
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Se guardó en tu dispositivo, pero no se pudo sincronizar con tu cuenta: $e')),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, true);
    }
  }

  Future<void> _loadExistingStickers() async {
    if (widget.identifier == null) return;
    setState(() => _loadingStickers = true);
    try {
      if (widget.initialStickerUrls != null && widget.initialStickerUrls!.isNotEmpty) {
        // Si nos dan URLs (pack de Firestore), las descargamos.
        final downloadedStickers = <Uint8List>[];
        for (final url in widget.initialStickerUrls!) {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            downloadedStickers.add(response.bodyBytes);
          }
        }
        if (mounted) {
          setState(() => _stickers.addAll(downloadedStickers));
        }
      } else {
        // Si no, cargamos desde el almacenamiento local (pack anónimo o ya existente localmente).
        final List<Uint8List>? stickerBytes =
            await _channel.invokeListMethod<Uint8List>('getStickersForPack', {'identifier': widget.identifier});
        if (stickerBytes != null && mounted) {
          setState(() {
            _stickers.addAll(stickerBytes);
          });
        }
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Error cargando stickers: ${e.message}');
    } finally {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  Future<void> _deletePack() async {
    if (widget.identifier == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar pack?'),
        content: Text('Se eliminará "${_nameController.text}" y todos sus stickers. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true); // Confirm delete
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        setState(() => _saving = true); // Show loading indicator on save button
        await _favoritesRepo.removeFavorite(widget.identifier!);
        await _channel.invokeMethod('deleteStickerPack', {'identifier': widget.identifier!});
        // Pop the edit screen and signal a refresh to the screen below (pack_preview)
        if (mounted) Navigator.pop(context, true);
      } on PlatformException catch (e) {
        if (mounted) {
          setState(() => _status = 'Error al eliminar: ${e.message}');
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _handlePrivacyToggle() async {
    if (widget.identifier == null) return;

    setState(() {
      _saving = true;
      _status = '';
    });

    try {
      if (_isPrivate) {
        // Acción: Hacer público (Publicar)
        if (_auth.isAnonymous) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Se requiere una cuenta'),
              content: const Text(
                  'Para poder publicar packs, necesitas vincular tu cuenta con Google. Esto nos ayuda a asignarte la autoría de tus creaciones.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _auth.linkWithGoogle();
                      setState(() {}); // Re-render para reflejar el estado del login
                    },
                    child: const Text('Iniciar sesión con Google')),
              ],
            ),
          );
          if (_auth.isAnonymous) return; // El usuario canceló o cerró el diálogo
        }

        if (_stickers.isEmpty && widget.isEditing) await _loadExistingStickers();
        if (_stickers.isEmpty) throw Exception('No hay stickers en el pack para publicar.');

        final uploadResult = await _storage.uploadPack(
          authorUid: _auth.currentUid!,
          packId: widget.identifier!,
          trayBytes: _stickers.first,
          stickerBytes: _stickers,
        );

        await _firestore.publishPack(
          packId: widget.identifier!,
          name: _nameController.text.trim(),
          authorUid: _auth.currentUid!,
          authorName: widget.publisher ?? 'Anónimo',
          trayUrl: uploadResult.trayUrl,
          stickers: uploadResult.stickerUrls.map((url) => {'url': url, 'emojis': ['😀']}).toList(),
        );
      } else {
        // Acción: Hacer privado (Quitar de la lista pública)
        await _firestore.unpublishPack(widget.identifier!);
      }

      // Finalmente, cambiamos el estado local en el dispositivo
      await _channel.invokeMethod('togglePackPrivacy', {'identifier': widget.identifier!, 'isPrivate': !_isPrivate});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isPrivate ? 'Pack publicado con éxito' : 'El pack ahora es privado')));
        Navigator.pop(context, true); // Pop y señal de refresco
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar pack' : 'Crear nuevo pack'),
        actions: [
          if (widget.isEditing)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'delete':
                    _deletePack();
                    break;
                  case 'private':
                    _handlePrivacyToggle();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'private', child: Text(_isPrivate ? 'Hacer público (publicar)' : 'Hacer privado')),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                    value: 'delete', child: Text('Eliminar pack', style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
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

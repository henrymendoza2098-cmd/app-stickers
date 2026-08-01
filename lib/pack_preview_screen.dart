import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mock_data.dart';
import 'create_pack_screen.dart';
import 'favorites_repository.dart';
import 'page_transitions.dart';
import 'profile_screen.dart';

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
  final String? publisherId;
  final int stickerCount;
  final bool isPrivate;

  const PackPreviewScreen({
    super.key,
    this.realIdentifier,
    this.mockPack,
    required this.packName,
    this.publisherName,
    this.publisherId,
    required this.stickerCount,
    this.isPrivate = false,
  });

  @override
  State<PackPreviewScreen> createState() => _PackPreviewScreenState();
}

class _PackPreviewScreenState extends State<PackPreviewScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Uint8List> _stickers = [];
  bool _loading = true;
  final _favoritesRepo = FavoritesRepository();

  bool get _isMock => widget.realIdentifier == null;
  bool get _isOwner => widget.publisherId == currentUserId;

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

  Future<void> _editPack() async {
    if (widget.realIdentifier == null) return;

    final updated = await Navigator.push<bool>(
      context,
      slideUpRoute(
        CreatePackScreen(
          packName: widget.packName,
          publisher: widget.publisherName,
          identifier: widget.realIdentifier,
          isEditing: true,
        ),
      ),
    );

    if (updated == true && mounted) {
      Navigator.pop(context, true); // Pop back to gallery/profile and signal a refresh
    }
  }

  Future<void> _deletePack() async {
    if (widget.realIdentifier == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar pack?'),
        content: Text('Se eliminará "${widget.packName}" y todos sus stickers. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _favoritesRepo.removeFavorite(widget.realIdentifier!);
        await _channel.invokeMethod('deleteStickerPack', {'identifier': widget.realIdentifier!});
        if (mounted) Navigator.pop(context, true); // Pop back and signal a refresh
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al eliminar: ${e.message}')));
        }
      }
    }
  }

  void _togglePrivate() async {
    if (widget.realIdentifier == null) return;
    try {
      await _channel.invokeMethod('togglePackPrivacy', {
        'identifier': widget.realIdentifier!,
        'isPrivate': !widget.isPrivate,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isPrivate ? 'Pack hecho público' : 'Pack hecho privado')),
        );
        Navigator.pop(context, true); // Pop back and signal a refresh
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mock = widget.mockPack;

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: ElevatedButton.icon(
          onPressed: _download,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          label: const Text('Añadir a WhatsApp'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: const StadiumBorder(),
          ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(widget.packName),
              pinned: true,
              actions: [
                if (_isOwner && !_isMock)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editPack();
                          break;
                        case 'delete':
                          _deletePack();
                          break;
                        case 'private':
                          _togglePrivate();
                          break;
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(value: 'edit', child: Text('Editar pack')),
                      PopupMenuItem<String>(value: 'private', child: Text(widget.isPrivate ? 'Hacer público' : 'Hacer privado')),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                          value: 'delete', child: Text('Eliminar pack', style: TextStyle(color: Colors.red))),
                    ],
                  )
              ],
            ),
            SliverToBoxAdapter(
              child: _buildHeader(context),
            ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_isMock)
              _MockStickerGrid(mock: mock!)
            else if (_stickers.isEmpty)
              const SliverFillRemaining(child: Center(child: Text('Este pack no tiene stickers')))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), // Padding for FAB
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _StickerGridTile(stickerBytes: _stickers[index]),
                    childCount: _stickers.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.packName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatItem(value: '${widget.stickerCount}', label: 'stickers'),
                    const SizedBox(width: 16),
                    _StatItem(value: '—', label: 'descargas'), // Placeholder
                    const SizedBox(width: 16),
                    _StatItem(value: '—', label: 'vistas'), // Placeholder
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (widget.publisherName != null && widget.publisherName!.isNotEmpty)
            _PublisherCard(
              publisherName: widget.publisherName!,
              publisherId: widget.publisherId,
            ),
        ],
      ),
    );
  }
}

class _PublisherCard extends StatelessWidget {
  final String publisherName;
  final String? publisherId;

  const _PublisherCard({required this.publisherName, this.publisherId});

  @override
  Widget build(BuildContext context) {
    final cardContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TODO: Usar el avatar real del creador cuando esté disponible
          CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey.shade200,
              child: Icon(Icons.person, size: 14, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          Text(publisherName, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (publisherId != null) const SizedBox(width: 4),
          if (publisherId != null) const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        ],
      ),
    );

    // Si no hay ID, la tarjeta no es interactiva
    if (publisherId == null) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: cardContent,
      );
    }

    // Si hay ID, la tarjeta es un botón que navega al perfil
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            slideUpRoute(ProfileScreen(profileId: publisherId!, userId: currentUserId)),
          );
        },
        child: cardContent,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }
}

class _StickerGridTile extends StatelessWidget {
  final Uint8List stickerBytes;

  const _StickerGridTile({required this.stickerBytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.memory(stickerBytes, fit: BoxFit.contain),
    );
  }
}

class _MockStickerGrid extends StatelessWidget {
  final MockPack mock;
  const _MockStickerGrid({required this.mock});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: mock.stickerCount,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(mock.previewIcon, color: mock.previewColor, size: 40),
        ),
      ),
    );
  }
}

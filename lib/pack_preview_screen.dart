import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'mock_data.dart';
import 'favorites_repository.dart';
import 'page_transitions.dart';
import 'profile_screen.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'supabase_storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:whatsapp_stickers_app/favorites_repository.dart';
import 'package:whatsapp_stickers_app/firestore_service.dart';
import 'package:whatsapp_stickers_app/page_transitions.dart';
import 'package:whatsapp_stickers_app/profile_screen.dart';
import 'package:whatsapp_stickers_app/sticker_preview_grid.dart';

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
  final String realIdentifier;
  final String packName;
  final String? publisherName;
  final String? publisherId;
  final int stickerCount;
  final bool isPrivate;

  const PackPreviewScreen({
    super.key,
    this.realIdentifier,
    this.mockPack,
    required this.realIdentifier,
    required this.packName,
    this.publisherName,
    this.publisherId,
    required this.stickerCount,
    this.isPrivate = false,
    required this.isPrivate,
  });

  @override
  State<PackPreviewScreen> createState() => _PackPreviewScreenState();
}

class _PackPreviewScreenState extends State<PackPreviewScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Uint8List> _stickers = [];
  bool _loading = true;
  bool _isSaving = false;
  final _firestore = FirestoreService.instance;
  final _favoritesRepo = FavoritesRepository();

  // Servicios
  final _auth = AuthService.instance;
  final _firestore = FirestoreService.instance;
  final _storage = SupabaseStorageService.instance;
  Map<String, dynamic>? _packData;
  Map<String, dynamic>? _authorData;
  Uint8List? _authorAvatar;
  bool _isFavorite = false;
  bool _isLoading = true;

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
    _loadData();
  }

  Future<void> _loadRealStickers() async {
  Future<void> _loadData() async {
    try {
      final stickers = await _channel
          .invokeListMethod<Uint8List>('getStickersForPack', {'identifier': widget.realIdentifier});
      if (mounted) setState(() => _stickers = stickers ?? []);
    } finally {
      if (mounted) setState(() => _loading = false);
      final futures = <Future<dynamic>>[
        _firestore.fetchPack(widget.realIdentifier),
        _favoritesRepo.getFavorites(),
      ];
      if (widget.publisherId != null) {
        futures.add(_firestore.fetchUserProfile(widget.publisherId!));
      }

      final results = await Future.wait(futures);

      final packData = results[0] as Map<String, dynamic>?;
      final favorites = results[1] as List<Map<String, dynamic>>;

      Map<String, dynamic>? authorData;
      if (widget.publisherId != null && results.length > 2) {
        authorData = results[2] as Map<String, dynamic>?;
      }

      if (packData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final isFav = favorites.any((p) => p['identifier'] == widget.realIdentifier);

      if (authorData != null) {
        final avatarUrl = authorData['avatarUrl'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(avatarUrl));
            if (response.statusCode == 200) {
              _authorAvatar = response.bodyBytes;
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _packData = packData;
          _authorData = authorData;
          _isFavorite = isFav;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
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
  Future<void> _toggleFavorite() async {
    if (_packData == null) return;
    final currentFavStatus = _isFavorite;
    setState(() => _isFavorite = !currentFavStatus);
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
      if (!currentFavStatus) {
        await _favoritesRepo.addFavorite(_packData!);
      } else {
        await _favoritesRepo.removeFavorite(widget.realIdentifier);
      }
    } catch (e) {
      setState(() => _isFavorite = currentFavStatus); // revert on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar en favoritos: $e')),
        );
      }
    }
  }

  void _openAuthorProfile() {
    if (widget.publisherId == null) return;
    Navigator.push(
      context,
      slideUpRoute(ProfileScreen(profileId: widget.publisherId!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mock = widget.mockPack;
    final stickerUrls = (_packData?['stickers'] as List?)?.map((s) => s['url'] as String).toList();
    final views = _packData?['views'] as int? ?? 0;
    final downloads = _packData?['downloads'] as int? ?? 0;

    return DefaultTabController(
      length: 1,
      child: Scaffold(
        floatingActionButtonLocation: _isOwner ? null : FloatingActionButtonLocation.centerFloat,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del paquete 📦'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Añadir a favoritos',
            icon: Icon(
              _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _isFavorite ? Colors.redAccent : null,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.packName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            onPressed: _isLoading ? null : _toggleFavorite,
          ),
          if (widget.publisherName != null && widget.publisherName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: widget.publisherId != null
                  ? () {
                      Navigator.push(
                        context,
                        slideUpRoute(ProfileScreen(profileId: widget.publisherId!)),
                      );
                    }
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('de ${widget.publisherName!}', style: Theme.of(context).textTheme.titleMedium),
                  if (widget.publisherId != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade700),
                  ]
                ],
              ),
            )
          ],
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
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _packData == null
              ? const Center(child: Text('No se pudo cargar el paquete.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.packName,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.stickerCount} stickers · $views vistas · $downloads descargas',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (widget.publisherId != null)
                          _AuthorPreviewCard(
                            authorData: _authorData,
                            authorAvatar: _authorAvatar,
                            onTap: _openAuthorProfile,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    StickerPreviewGrid(
                      previewStickerUrls: stickerUrls,
                      crossAxisCount: 3,
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Lógica para añadir a WhatsApp
        },
        label: const Text('Añadir a WhatsApp'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
class _AuthorPreviewCard extends StatelessWidget {
  final Map<String, dynamic>? authorData;
  final Uint8List? authorAvatar;
  final VoidCallback onTap;

  const _StatItem({required this.value, required this.label});
  const _AuthorPreviewCard({
    required this.authorData,
    this.authorAvatar,
    required this.onTap,
  });

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
    final authorName = authorData?['name'] as String? ?? 'Autor desconocido';

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
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: authorAvatar != null ? MemoryImage(authorAvatar!) : null,
                child: authorAvatar == null ? const Icon(Icons.person, size: 16, color: Colors.grey) : null,
              ),
              const SizedBox(width: 8),
              Text(
                authorName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
            ],
          ),
          child: Icon(mock.previewIcon, color: mock.previewColor, size: 40),
        ),
      ),
    );
  }
}

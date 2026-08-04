import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'auth_service.dart';
import 'firestore_service.dart';
import 'create_pack_screen.dart';
import 'favorites_repository.dart';
import 'page_transitions.dart';
import 'profile_screen.dart';
import 'pack_preview_screen.dart';
import 'mock_data.dart';
import 'sticker_preview_grid.dart';
import 'creators_feed.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Map<String, dynamic>> _packs = [];
  bool _loading = true;

  // Servicios
  final _firestore = FirestoreService.instance;
  final _auth = AuthService.instance;
  final _favoritesRepo = FavoritesRepository();
  List<String> _favoritePackIds = [];

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPacks = [];
  String _selectedFilter = 'Todo';

  @override
  void initState() {
    super.initState();
    loadPacks();
    _loadFavorites();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favs = await _favoritesRepo.getFavorites();
    if (!mounted) return;
    setState(() {
      _favoritePackIds = favs.map((p) => p['identifier'] as String).toList();
    });
  }

  Future<void> _toggleFavorite(Map<String, dynamic> pack) async {
    final identifier = pack['identifier'] as String;
    if (_favoritePackIds.contains(identifier)) {
      await _favoritesRepo.removeFavorite(identifier);
    } else {
      await _favoritesRepo.addFavorite(pack);
    }
    await _loadFavorites();
  }

  void _editPack(Map<String, dynamic> pack) {
    final identifier = pack['identifier'] as String;
    final name = pack['name'] as String;
    // En packs de Firestore, el autor es 'authorName'. En locales, 'publisher'.
    final publisher = (pack['authorName'] ?? pack['publisher']) as String? ?? '';
    // CORRECCIÓN: Usar 'isPublic' de Firestore. Un pack es privado si 'isPublic' no es true.
    final isPrivate = !(pack['isPublic'] as bool? ?? false);

    Navigator.push<bool>(
      context,
      slideUpRoute(
        CreatePackScreen(
            packName: name, publisher: publisher, identifier: identifier, isEditing: true, isPrivate: isPrivate),
      ),
    ).then((updated) => {if (updated == true) loadPacks()});
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _updateFilteredPacks();
    });
  }

  void _updateFilteredPacks() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredPacks = List.from(_packs);
    } else {
      _filteredPacks = _packs.where((pack) {
        final name = (pack['name'] as String? ?? '').toLowerCase();
        return name.contains(query);
      }).toList();
    }
  }

  Future<void> loadPacks() async {
    setState(() => _loading = true);
    try {
      _packs = await _firestore.fetchFeedPacks();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando feed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _updateFilteredPacks();
        });
      }
    }
  }

  Future<void> _addToWhatsApp(String identifier, String name) async {
    // TODO: Implementar la descarga de packs de la comunidad.
    // Por ahora, el botón "Añadir" es una demo para packs que no son del usuario.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Añadir packs de la comunidad (próximamente)')),
    );
    return;

    // El código original que solo funciona para packs locales:
    /*
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
    }*/
  }

  Future<void> _deletePack(String identifier) async {
    await _favoritesRepo.removeFavorite(identifier);
    await _channel.invokeMethod('deleteStickerPack', {'identifier': identifier});
    await loadPacks();
    await _loadFavorites();
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

  void _openPack(Map<String, dynamic> pack) {
    final identifier = pack['identifier'] as String;
    final name = pack['name'] as String;
    final publisher = pack['authorName'] as String? ?? '';
    final stickerCount = pack['stickerCount'] as int? ?? 0;
    final isPublic = pack['isPublic'] as bool? ?? true;
    final publisherId = pack['authorUid'] as String?;

    // Incrementamos las vistas en Firestore sin esperar a que termine.
    _firestore.incrementPackViews(identifier);

    Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => PackPreviewScreen(
              realIdentifier: identifier,
              packName: name,
              publisherName: publisher,
              stickerCount: stickerCount,
              publisherId: publisherId,
              isPrivate: !isPublic)),
    ).then((refreshed) {
      if (refreshed == true) {
        loadPacks();
        _loadFavorites();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildGalleryBody(colorScheme),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePackSheet,
        tooltip: 'Crear pack',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGalleryBody(ColorScheme colorScheme) {
    if (_packs.isEmpty && _selectedFilter != 'Perfiles') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 48, color: colorScheme.primary.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                'Todavía no tienes packs.\nCrea el primero con el botón +',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadPacks,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar packs por nombre...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          _FilterBar(
            selectedFilter: _selectedFilter,
            onFilterSelected: (filter) => setState(() => _selectedFilter = filter),
          ),
          Expanded(
            child: _buildContentForFilter(),
          ),
        ],
      ),
    );
  }

  Widget _buildContentForFilter() {
    if (_selectedFilter == 'Perfiles') {
      return const CreatorsFeed();
    }

    if (_filteredPacks.isEmpty && _searchController.text.isNotEmpty) {
      return _buildNoResults();
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      itemCount: _filteredPacks.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final pack = _filteredPacks[index];
        final identifier = pack['identifier'] as String;
        final name = pack['name'] as String? ?? 'Pack sin nombre';
        final stickerUrls = (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList();
        final isOwner = pack['authorUid'] == _auth.currentUid;
        final isFavorite = _favoritePackIds.contains(identifier);
        final isPublic = pack['isPublic'] as bool? ?? true;

        return _PackRow(
          pack: pack,
          trayUrl: pack['trayUrl'] as String?,
          previewStickerUrls: stickerUrls,
          onTap: () => _openPack(pack),
          onAdd: () => _addToWhatsApp(identifier, name),
          isFavorite: isFavorite,
          onToggleFavorite: () => _toggleFavorite(pack),
          isOwner: isOwner,
          isPrivate: !isPublic,
          onEdit: () => _editPack(pack),
          onDelete: () => _confirmDelete(identifier, name),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No se encontraron packs para "${_searchController.text}"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
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

class _FilterBar extends StatelessWidget {
  final List<String> filters = const ['Todo', 'Perfiles', 'Siguiendo', 'Amor', 'Memes', 'Alegría', 'Reacciones'];
  final String selectedFilter;
  final ValueChanged<String> onFilterSelected;

  const _FilterBar({
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((filter) {
          final bool isSelected = selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) onFilterSelected(filter);
              },
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              selectedColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide.none,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  final Map<String, dynamic> pack;
  final String? trayUrl;
  final List<String>? previewStickerUrls;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool isPrivate;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PackRow({
    required this.pack,
    this.trayUrl,
    this.previewStickerUrls,
    required this.onTap,
    required this.onAdd,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.isPrivate,
    required this.isOwner,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = pack['name'] as String? ?? 'Pack sin nombre';
    final publisher = (pack['authorName'] ?? pack['publisher']) as String? ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (publisher.isNotEmpty)
                        Text(publisher, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.redAccent : Colors.grey,
                  ),
                  onPressed: onToggleFavorite,
                  tooltip: 'Marcar como favorito',
                ),
                if (isOwner)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
                    ],
                  )
                else
                  TextButton(onPressed: onAdd, child: const Text('Añadir')),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: (previewStickerUrls == null || previewStickerUrls!.isEmpty)
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: trayUrl != null ? Image.network(trayUrl!, fit: BoxFit.contain) : Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: previewStickerUrls!.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        return AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Image.network(previewStickerUrls![index], fit: BoxFit.contain),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

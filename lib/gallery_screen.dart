import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'create_pack_screen.dart';
import 'favorites_repository.dart';
import 'page_transitions.dart';
import 'profile_screen.dart';
import 'pack_preview_screen.dart';
import 'mock_data.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  List<Map<String, dynamic>> _packs = [];
  final Map<String, Uint8List> _trayCache = {};
  final Map<String, List<Uint8List>> _previewStickersCache = {};
  bool _loading = true;

  final _favoritesRepo = FavoritesRepository();
  List<String> _favoritePackIds = [];

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredPacks = [];

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

  Future<void> _togglePrivacy(String identifier, bool isCurrentlyPrivate) async {
    try {
      await _channel.invokeMethod('togglePackPrivacy', {
        'identifier': identifier,
        'isPrivate': !isCurrentlyPrivate,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isCurrentlyPrivate ? 'Pack hecho público' : 'Pack hecho privado')),
        );
      }
      await loadPacks();
      await _loadFavorites();
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    }
  }

  void _editPack(Map<String, dynamic> pack) {
    final identifier = pack['identifier'] as String;
    final name = pack['name'] as String;
    final publisher = pack['publisher'] as String? ?? '';
    Navigator.push<bool>(
      context,
      slideUpRoute(CreatePackScreen(packName: name, publisher: publisher, identifier: identifier, isEditing: true)),
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
    _filteredPacks = _packs.where((pack) {
      final name = (pack['name'] as String? ?? '').toLowerCase();
      final isPrivate = pack['isPrivate'] as bool? ?? false;
      return name.contains(query) && !isPrivate;
    }).toList();
  }

  Future<void> loadPacks() async {
    setState(() => _loading = true);

    // Usar datos de prueba en plataformas de escritorio para facilitar el desarrollo
    final isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    if (!isMobile) {
      _loadMockPacksForDesktop();
      return;
    }

    try {
      final jsonStr = await _channel.invokeMethod<String>('getStickerPacks');
      final List<dynamic> list = jsonDecode(jsonStr ?? '[]');
      _packs = list.cast<Map<String, dynamic>>();

      for (final pack in _packs) {
        final id = pack['identifier'] as String;
        final isDynamic = pack['isDynamic'] as bool? ?? false;

        if (!_trayCache.containsKey(id)) {
          final bytes = await _channel.invokeMethod<Uint8List>('getPackTray', {'identifier': id});
          if (bytes != null) _trayCache[id] = bytes;
        }
        if (isDynamic && !_previewStickersCache.containsKey(id)) {
          final stickerBytesList = await _channel.invokeMethod<List<dynamic>>('getFirstNStickersForPack', {'identifier': id, 'count': 4});
          if (stickerBytesList != null)
            _previewStickersCache[id] = stickerBytesList.cast<Uint8List>();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando packs: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _updateFilteredPacks();
        });
      }
    }
  }

  /// Carga paquetes de stickers falsos para pruebas en escritorio/web.
  void _loadMockPacksForDesktop() {
    _packs = [
      {
        'identifier': 'desktop_pack_memes',
        'name': 'Memes para PC',
        'publisher': 'Usuario de Desktop',
        'stickerCount': 12,
        'isDynamic': true,
      },
      {
        'identifier': 'desktop_pack_code',
        'name': 'Stickers de Programación',
        'publisher': 'Gemini',
        'stickerCount': 20,
        'isDynamic': true,
      },
      {
        'identifier': 'desktop_pack_dogs',
        'name': 'Perritos para alegrar el día',
        'publisher': 'Amante de los animales',
        'stickerCount': 8,
        'isDynamic': false,
      },
    ];
    // No hay previews de stickers en la web, se mostrará el icono por defecto.
    _previewStickersCache.clear();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _loading = false;
          _updateFilteredPacks();
        });
      }
    });
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
    await _favoritesRepo.removeFavorite(identifier);
    await _channel.invokeMethod('deleteStickerPack', {'identifier': identifier});
    _trayCache.remove(identifier);
    _previewStickersCache.remove(identifier);
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
    final publisher = pack['publisher'] as String? ?? '';
    final isDynamic = pack['isDynamic'] as bool? ?? false;
    final stickerCount = pack['stickerCount'] as int? ?? 0;
    final isPrivate = pack['isPrivate'] as bool? ?? false;

    // Si es un pack dinámico (creado por el usuario), le asignamos el ID del
    // usuario actual para que la tarjeta de autor lleve a su perfil.
    // Para packs de demo, el publisherId será null.
    final publisherId = isDynamic ? currentUserId : null;

    Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => PackPreviewScreen(
              realIdentifier: identifier,
              packName: name,
              publisherName: publisher,
              stickerCount: stickerCount,
              publisherId: publisherId,
              isPrivate: isPrivate)),
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
        tooltip: 'Agregar',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGalleryBody(ColorScheme colorScheme) {
    if (_packs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 48, color: colorScheme.primary.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text(
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
          const _FilterBar(),
          Expanded(
            child: _filteredPacks.isEmpty && _searchController.text.isNotEmpty
                ? _buildNoResults()
                : ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: _filteredPacks.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                final pack = _filteredPacks[index];
                final identifier = pack['identifier'] as String;
                final name = pack['name'] as String;
                final publisher = pack['publisher'] as String? ?? '';
                final isDynamic = pack['isDynamic'] as bool? ?? false;
                final previewStickers = kIsWeb ? null : _previewStickersCache[identifier];
                final isFavorite = _favoritePackIds.contains(identifier);
                final isPrivate = pack['isPrivate'] as bool? ?? false;

                return _PackRow(
                  pack: pack,
                  previewStickers: previewStickers,
                  onTap: () => _openPack(pack),
                  onAdd: () => _addToWhatsApp(identifier, name),
                  isFavorite: isFavorite,
                  onToggleFavorite: () => _toggleFavorite(pack),
                  isDynamic: isDynamic,
                  isPrivate: isPrivate,
                  onEdit: () => _editPack(pack),
                  onDelete: () => _confirmDelete(identifier, name),
                  onTogglePrivate: () => _togglePrivacy(identifier, isPrivate),
                );
              },
            ),
          ),
        ],
      ),
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

class _FilterBar extends StatefulWidget {
  const _FilterBar();

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final List<String> _filters = ['Todo', 'Perfiles', 'Siguiendo', 'Amor', 'Memes', 'Alegría', 'Reacciones'];
  String _selectedFilter = 'Todo';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _filters.map((filter) {
          final bool isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedFilter = filter);
                  // Aquí se implementaría la lógica de filtrado en el futuro
                }
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
  final List<Uint8List>? previewStickers;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool isDynamic;
  final bool isPrivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePrivate;

  const _PackRow({
    required this.pack,
    this.previewStickers,
    required this.onTap,
    required this.onAdd,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.isDynamic,
    required this.isPrivate,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePrivate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = pack['name'] as String;
    final publisher = pack['publisher'] as String? ?? '';

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
                if (isDynamic)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'private':
                          onTogglePrivate();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'private', child: Text(isPrivate ? 'Hacer público' : 'Hacer privado')),
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
              child: (previewStickers == null || previewStickers!.isEmpty)
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: previewStickers!.length,
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
                            child: Image.memory(previewStickers![index], fit: BoxFit.contain),
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

/// Grid de preview para los stickers en la tarjeta del pack.
class StickerPreviewGrid extends StatelessWidget {
  final List<Uint8List>? previewStickers;

  const StickerPreviewGrid({super.key, this.previewStickers});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Builder(
      builder: (context) {
        if (previewStickers == null || previewStickers!.isEmpty) {
          return Center(child: Icon(Icons.image_rounded, size: 48, color: colorScheme.primary.withOpacity(0.35)));
        }

        // Estilo de cuadrícula minimalista
        final stickersToDisplay = previewStickers!.take(4).toList();

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: stickersToDisplay.length,
          itemBuilder: (context, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(stickersToDisplay[index], fit: BoxFit.contain),
            );
          },
        );
      },
    );
  }
}
 

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'favorites_repository.dart';
import 'mock_data.dart';
import 'create_pack_screen.dart';
import 'crop_screen.dart';
import 'pack_preview_screen.dart';
import 'gallery_screen.dart';
import 'edit_profile_screen.dart';
import 'page_transitions.dart';

/// Pantalla de perfil con doble modo:
/// - MODO PERSONAL: profileId == currentUserId → panel de gestión propio,
///   con TU nombre/fotos reales (guardados en el dispositivo) y TODOS tus
///   packs reales.
/// - MODO VISITANTE: profileId de otro creador → vitrina pública simulada,
///   solo con los packs marcados como públicos, sin accesos de edición.
class ProfileScreen extends StatefulWidget {
  final String profileId;
  const ProfileScreen({super.key, required this.profileId, required String userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');

  bool get _isOwner => widget.profileId == currentUserId;

  // --- Perfil real (nombre, username, fotos) — solo modo dueño ---
  String _realName = '';
  String _realUsername = '';
  String _realBio = '';
  Uint8List? _realAvatar;
  Uint8List? _realCover;
  bool _loadingProfile = true;

  // --- Packs reales — solo modo dueño ---
  List<Map<String, dynamic>> _realPacks = [];
  List<Map<String, dynamic>> _privatePacks = [];
  final Map<String, List<Uint8List>> _realPreviewCache = {};
  bool _loadingPacks = true;

  // --- Favoritos ---
  final _favoritesRepo = FavoritesRepository();
  List<Map<String, dynamic>> _favoritePacks = [];
  bool _loadingFavorites = true;

  int _profileTab = 0; // 0 = Mis stickers, 1 = Favoritos, 2 = Privados

  @override
  void initState() {
    super.initState();
    if (_isOwner) {
      _loadProfile();
      _loadRealPacks();
      _loadFavorites();
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final jsonStr = await _channel.invokeMethod<String>('getProfile');
      final Map<String, dynamic> data = jsonDecode(jsonStr ?? '{}');
      _realName = (data['name'] as String?) ?? '';
      _realUsername = (data['username'] as String?) ?? '';
      _realBio = (data['bio'] as String?) ?? '';
      final hasAvatar = data['hasAvatar'] == true;
      final hasCover = data['hasCover'] == true;
      _realAvatar = hasAvatar ? await _channel.invokeMethod<Uint8List>('getProfileAvatar') : null;
      _realCover = hasCover ? await _channel.invokeMethod<Uint8List>('getProfileCover') : null;
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadRealPacks() async {
    setState(() => _loadingPacks = true);
    try {
      final jsonStr = await _channel.invokeMethod<String>('getStickerPacks');
      final List<dynamic> list = jsonDecode(jsonStr ?? '[]');
      final allUserPacks = list.cast<Map<String, dynamic>>().where((p) => p['isDynamic'] == true).toList();

      _realPacks = allUserPacks.where((p) => p['isPrivate'] != true).toList();
      _privatePacks = allUserPacks.where((p) => p['isPrivate'] == true).toList();

      for (final pack in allUserPacks) {
        final id = pack['identifier'] as String;
        if (!_realPreviewCache.containsKey(id)) {
          try {
            final stickers = await _channel.invokeListMethod<Uint8List>('getFirstNStickersForPack', {'identifier': id, 'count': 4});
            if (stickers != null) _realPreviewCache[id] = stickers.take(4).toList();
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => _loadingPacks = false);
    }
  }

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    setState(() => _loadingFavorites = true);
    try {
      _favoritePacks = await _favoritesRepo.getFavorites();
      // Cargar también las vistas previas de los stickers para los packs dinámicos favoritos
      for (final pack in _favoritePacks) {
        final id = pack['identifier'] as String;
        if (!_realPreviewCache.containsKey(id) && (pack['isDynamic'] as bool? ?? false)) {
          try {
            final stickers = await _channel.invokeListMethod<Uint8List>('getFirstNStickersForPack', {'identifier': id, 'count': 4});
            if (stickers != null) _realPreviewCache[id] = stickers.take(4).toList();
          } catch (_) {
            // En escritorio, esto fallará. La tarjeta mostrará un placeholder, lo cual está bien.
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loadingFavorites = false);
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.push<bool>(
      context,
      slideUpRoute(
        EditProfileScreen(
          currentName: _realName,
          username: _realUsername,
          currentBio: _realBio,
          currentAvatar: _realAvatar,
          currentCover: _realCover,
        ),
      ),
    );
    if (updated == true) {
      _loadProfile();
      _loadFavorites(); // Nombres/etc. de packs favoritos pueden haber cambiado
    }
  }

  Future<void> _createNewPack() async {
    final Uint8List? original = await _channel.invokeMethod<Uint8List>('pickImage');
    if (original == null || !mounted) return;

    final cropped = await Navigator.push<Uint8List>(
      context,
      slideUpRoute(CropScreen(imageBytes: original)),
    );
    if (cropped == null || !mounted) return;

    final created = await Navigator.push<bool>(
      context,
      slideUpRoute(CreatePackScreen(initialStickers: [cropped])),
    );
    if (created == true) {
      _loadRealPacks();
      _loadFavorites();
    }
  }

  void _openOwnedPack(Map<String, dynamic> pack) {
    final identifier = pack['identifier'] as String;
    final name = pack['name'] as String;
    final publisher = pack['publisher'] as String? ?? '';
    final stickerCount = pack['stickerCount'] as int? ?? 0;
    final isPrivate = pack['isPrivate'] as bool? ?? false;

    Navigator.push<bool>(
      context,
      slideUpRoute(
        PackPreviewScreen(
            realIdentifier: identifier,
            packName: name,
            publisherName: publisher,
            stickerCount: stickerCount,
            publisherId: currentUserId, // Es un pack propio
            isPrivate: isPrivate),
      ),
    ).then((refreshed) {
      if (refreshed == true) {
        _loadRealPacks();
        _loadFavorites();
      }
    });
  }

  void _openVisitorPack(MockPack pack, MockProfile profile) {
    Navigator.push(
      context,
      slideUpRoute(PackPreviewScreen(
        mockPack: pack,
        packName: pack.name,
        publisherName: profile.name,
        publisherId: profile.id,
        stickerCount: pack.stickerCount,
      )),
    );
  }

  void _openDemoVisitorProfile() {
    Navigator.push(
      context,
      slideUpRoute(ProfileScreen(profileId: demoVisitorProfile.id, userId: currentUserId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final MockProfile? visitorProfile = _isOwner ? null : findMockProfile(widget.profileId);
    if (!_isOwner && visitorProfile == null) {
      return const Scaffold(body: Center(child: Text('Perfil no encontrado')));
    }

    if (_isOwner && _loadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            actions: [
              if (_isOwner)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Ajustes',
                  onPressed: () {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Ajustes (próximamente)')));
                  },
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: _isOwner
                ? _ProfileHeader(
                    name: _realName.isEmpty ? _realUsername : _realName,
                    handle: '@$_realUsername',
                    bio: _realBio,
                    verified: false,
                    followers: 0,
                    avatarBytes: _realAvatar,
                    coverBytes: _realCover,
                    fallbackColorA: myMockProfileHeader.bannerColorA,
                    fallbackColorB: myMockProfileHeader.bannerColorB,
                    isOwner: true,
                    packCount: _realPacks.length,
                    onEditTap: _openEditProfile,
                  )
                : _ProfileHeader(
                    name: visitorProfile!.name,
                    handle: visitorProfile.handle,
                    bio: visitorProfile.bio,
                    verified: visitorProfile.verified,
                    followers: visitorProfile.followers,
                    avatarBytes: null,
                    coverBytes: null,
                    fallbackColorA: visitorProfile.bannerColorA,
                    fallbackColorB: visitorProfile.bannerColorB,
                    isOwner: false,
                    packCount: visitorProfile.packs.where((p) => p.isPublic).length,
                    onFollowTap: () =>
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seguir (demo)'))),
                  ),
          ),
          if (_isOwner)
            SliverToBoxAdapter(
              child: _ProfileTabs(selected: _profileTab, onChanged: (i) => setState(() => _profileTab = i)),
            ),
          if (_isOwner) ..._buildOwnerBodySlivers(colorScheme) else ..._buildVisitorPacksSlivers(visitorProfile!),
          if (_isOwner && _profileTab == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: OutlinedButton.icon(
                  onPressed: _openDemoVisitorProfile,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Ver perfil de ejemplo en modo visitante'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isOwner
          ? FloatingActionButton(
              onPressed: _createNewPack,
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
    );
  }

  List<Widget> _buildOwnerBodySlivers(ColorScheme colorScheme) {
    if (_profileTab == 1) {
      return _buildFavoritePacksSlivers(colorScheme);
    }
    if (_profileTab == 2) return _buildPrivatePacksSlivers(colorScheme);
    return _buildOwnerPacksSlivers(colorScheme);
  }

  List<Widget> _buildOwnerPacksSlivers(ColorScheme colorScheme) {
    if (_loadingPacks) {
      return [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_realPacks.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 44, color: colorScheme.primary.withValues(alpha: 0.35)),
                const SizedBox(height: 10),
                const Text('Aún no has creado ningún pack', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pack = _realPacks[index];
              final identifier = pack['identifier'] as String;
              return _RealPackCard(
                pack: pack,
                previewStickers: _realPreviewCache[identifier] ?? const [],
                onTap: () => _openOwnedPack(pack),
              );
            },
            childCount: _realPacks.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildPrivatePacksSlivers(ColorScheme colorScheme) {
    if (_loadingPacks) {
      return [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_privatePacks.isEmpty) {
      return [
        const _PlaceholderTabSliver(
          icon: Icons.lock_outline_rounded,
          title: 'Sin packs privados',
          subtitle: 'Los packs que marques como privados aparecerán aquí.',
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pack = _privatePacks[index];
              return _RealPackCard(
                pack: pack,
                previewStickers: _realPreviewCache[pack['identifier'] as String] ?? const [],
                onTap: () => _openOwnedPack(pack),
              );
            },
            childCount: _privatePacks.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildFavoritePacksSlivers(ColorScheme colorScheme) {
    if (_loadingFavorites) {
      return [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_favoritePacks.isEmpty) {
      return [
        const _PlaceholderTabSliver(
          icon: Icons.favorite_border_rounded,
          title: 'Sin favoritos',
          subtitle: 'Tus packs favoritos aparecerán aquí.',
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pack = _favoritePacks[index];
              final identifier = pack['identifier'] as String;
              final isDynamic = pack['isDynamic'] as bool? ?? false;
              return _RealPackCard(
                pack: pack,
                previewStickers: _realPreviewCache[identifier] ?? const [],
                onTap: () {
                  if (isDynamic) {
                    _openOwnedPack(pack);
                  } else {
                    // Para packs favoritos que no son dinámicos (p. ej. el de demo),
                    // intentamos ver si el creador es el usuario actual para poder navegar a su perfil.
                    // Es una heurística simple; un sistema real guardaría el ID del creador.
                    final publisher = pack['publisher'] as String? ?? '';
                    final publisherId = (publisher.isNotEmpty && publisher == _realName) || (publisher.isEmpty)
                        ? currentUserId
                        : null;
                    final isPrivate = pack['isPrivate'] as bool? ?? false;

                    Navigator.push<bool>(
                      context,
                      slideUpRoute(PackPreviewScreen(
                          realIdentifier: identifier,
                          packName: pack['name'] as String,
                          publisherName: publisher,
                          stickerCount: pack['stickerCount'] as int? ?? 0,
                          publisherId: publisherId,
                          isPrivate: isPrivate)),
                    ).then((refreshed) {
                      if (refreshed == true) {
                        _loadRealPacks();
                        _loadFavorites();
                      }
                    });
                  }
                },
              );
            },
            childCount: _favoritePacks.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildVisitorPacksSlivers(MockProfile profile) {
    final publicPacks = profile.packs.where((p) => p.isPublic).toList();
    if (publicPacks.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Este creador aún no tiene packs públicos', style: TextStyle(color: Colors.grey))),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pack = publicPacks[index];
              return _MockPackCard(pack: pack, onTap: () => _openVisitorPack(pack, profile));
            },
            childCount: publicPacks.length,
          ),
        ),
      ),
    ];
  }
}

/// Fila de sub-pestañas: Mis stickers / Favoritos / Privados.
class _ProfileTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ProfileTabs({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabs = [
      (Icons.grid_view_rounded, 'Mis stickers'),
      (Icons.favorite_border_rounded, 'Favoritos'),
      (Icons.lock_outline_rounded, 'Privados'),
    ];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(tabs.length, (i) {
            final active = selected == i;
            final color = active ? colorScheme.primary : Colors.grey;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Icon(tabs[i].$1, color: color, size: 22),
                      const SizedBox(height: 4),
                      Container(
                        height: 2.5,
                        width: 28,
                        decoration: BoxDecoration(
                          color: active ? colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _PlaceholderTabSliver extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _PlaceholderTabSliver({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(icon, size: 44, color: colorScheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle ?? 'Próximamente', style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Cabecera del perfil: banner + avatar + nombre + bio + stats.
/// Sirve tanto para el perfil real (dueño) como para el simulado
/// (visitante) — recibe los bytes/colores ya resueltos.
class _ProfileHeader extends StatelessWidget {
  final String name;
  final String handle;
  final String bio;
  final bool verified;
  final int followers;
  final Uint8List? avatarBytes;
  final Uint8List? coverBytes;
  final Color fallbackColorA;
  final Color fallbackColorB;
  final bool isOwner;
  final int packCount;
  final VoidCallback? onFollowTap;
  final VoidCallback? onEditTap;

  const _ProfileHeader({
    required this.name,
    required this.handle,
    required this.bio,
    required this.verified,
    required this.followers,
    required this.avatarBytes,
    required this.coverBytes,
    required this.fallbackColorA,
    required this.fallbackColorB,
    required this.isOwner,
    required this.packCount,
    this.onFollowTap,
    this.onEditTap,
  });

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: coverBytes == null
                    ? LinearGradient(
                        colors: [fallbackColorA, fallbackColorB],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                image: coverBytes != null ? DecorationImage(image: MemoryImage(coverBytes!), fit: BoxFit.cover) : null,
              ),
            ),
            Positioned(
              left: 20,
              bottom: -32,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: fallbackColorA.withValues(alpha: 0.2),
                  backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes!) : null,
                  child: avatarBytes == null ? Icon(Icons.person_rounded, size: 36, color: fallbackColorA) : null,
                ),
              ),
            ),
            if (!isOwner)
              Positioned(
                right: 16,
                bottom: -18,
                child: ElevatedButton(
                  onPressed: onFollowTap,
                  style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text('Seguir'),
                ),
              )
            else
              Positioned(
                right: 16,
                bottom: -18,
                child: OutlinedButton(
                  onPressed: onEditTap,
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  child: const Text('Editar perfil'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 44),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  if (verified) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.verified_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
              Text(handle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(bio, style: const TextStyle(fontSize: 13.5)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!isOwner) ...[
                    _StatChip(value: _formatCount(followers), label: 'Seguidores'),
                    const SizedBox(width: 18),
                  ],
                  _StatChip(value: '$packCount', label: isOwner ? 'Packs creados' : 'Packs públicos'),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

/// Tarjeta de pack real (modo dueño), con previews reales del dispositivo.
class _RealPackCard extends StatelessWidget {
  final Map<String, dynamic> pack;
  final List<Uint8List> previewStickers;
  final VoidCallback onTap;

  const _RealPackCard({required this.pack, required this.previewStickers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _PackCardShell(
      onTap: onTap,
      title: pack['name'] as String,
      subtitle: '${pack['stickerCount']} stickers',
      showLock: true,
      preview: StickerPreviewGrid(previewStickers: previewStickers),
    );
  }
}

/// Tarjeta de pack simulado (modo visitante).
class _MockPackCard extends StatelessWidget {
  final MockPack pack;
  final VoidCallback onTap;

  const _MockPackCard({required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _PackCardShell(
      onTap: onTap,
      title: pack.name,
      subtitle: '${pack.stickerCount} stickers · ${_formatDownloads(pack.downloads)} descargas',
      showLock: false,
      preview: GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: List.generate(4, (i) => Icon(pack.previewIcon, color: pack.previewColor, size: 22)),
      ),
    );
  }

  String _formatDownloads(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Estructura visual compartida entre tarjetas reales y simuladas.
class _PackCardShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget preview;
  final bool showLock;
  final VoidCallback onTap;

  const _PackCardShell({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.showLock,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFF3F1F8),
                padding: const EdgeInsets.all(10),
                child: preview,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showLock) ...[
                        Icon(Icons.lock_outline_rounded, size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

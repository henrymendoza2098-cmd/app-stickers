import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:whatsapp_stickers_app/pack_preview_screen.dart';
import 'auth_service.dart';
import 'favorites_repository.dart';
import 'firestore_service.dart';
import 'package:whatsapp_stickers_app/supabase_storage_service.dart';
import 'mock_data.dart';
import 'create_pack_screen.dart';
import 'crop_screen.dart';
// import 'pack_preview_screen.dart'; // This import is not used, can be removed.
import 'edit_profile_screen.dart';
import 'page_transitions.dart';
import 'sticker_preview_grid.dart';

/// Objeto que devuelve `EditProfileScreen` cuando se guarda con éxito.
class EditProfileResult {
  final String name;
  final String bio;
  final Uint8List? newAvatarBytes;
  final Uint8List? newCoverBytes;

  EditProfileResult(
      {required this.name, required this.bio, this.newAvatarBytes, this.newCoverBytes});
}

/// Pantalla de perfil con doble modo:
/// - MODO PERSONAL: profileId == currentUserId → panel de gestión propio,
///   con TU nombre/fotos reales (guardados en el dispositivo) y TODOS tus
///   packs reales.
/// - MODO VISITANTE: profileId de otro creador → vitrina pública simulada,
///   solo con los packs marcados como públicos, sin accesos de edición.
class ProfileScreen extends StatefulWidget {
  final String profileId;
  const ProfileScreen({super.key, required this.profileId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');

  // Servicios
  final _auth = AuthService.instance;
  final _firestore = FirestoreService.instance;

  bool get _isOwner => widget.profileId == _auth.currentUid;

  // --- Perfil real (nombre, username, fotos) — solo modo dueño ---
  String _realName = '';
  String _realUsername = '';
  String _realBio = '';
  Uint8List? _realAvatar;
  int _realFollowingCount = 0;
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

  // --- Perfil de visitante ---
  Map<String, dynamic>? _visitorProfileData;
  Uint8List? _visitorAvatar;
  Uint8List? _visitorCover;
  List<Map<String, dynamic>> _visitorPacks = [];
  bool _loadingVisitorProfile = true;
  bool _isFollowing = false;
  bool _isTogglingFollow = false;

  int _profileTab = 0; // 0 = Mis stickers, 1 = Favoritos, 2 = Privados

  @override
  void initState() {
    super.initState();
    if (_isOwner) {
      _loadProfile();
      _loadRealPacks();
      _loadFavorites();
    } else {
      _loadVisitorProfile();
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    _realAvatar = null; // Limpiar imágenes anteriores para evitar mostrar las viejas
    _realCover = null;
    try {
      // Siempre cargamos los datos locales como base y fallback
      final localProfileJson = await _channel.invokeMethod<String>('getProfile');
      final Map<String, dynamic> localData = jsonDecode(localProfileJson ?? '{}');
      _realUsername = (localData['username'] as String?) ?? '';

      if (_isOwner && !_auth.isAnonymous && _auth.currentUid != null) {
        // USUARIO AUTENTICADO: Cargar de Firestore y usar local como fallback
        final firestoreData = await _firestore.fetchUserProfile(_auth.currentUid!);

        _realName = (firestoreData?['name'] as String?) ?? (localData['name'] as String?) ?? '';
        _realBio = (firestoreData?['bio'] as String?) ?? (localData['bio'] as String?) ?? '';
        _realFollowingCount = (firestoreData?['followingCount'] as int?) ?? 0;

        // Cargar imágenes desde URL de Firestore, o desde local si no hay URL
        final avatarUrl = firestoreData?['avatarUrl'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(avatarUrl));
            if (response.statusCode == 200) _realAvatar = response.bodyBytes;
          } catch (_) {} // Ignorar errores de red, se usará el local
        }
        if (_realAvatar == null && localData['hasAvatar'] == true) {
          _realAvatar = await _channel.invokeMethod<Uint8List>('getProfileAvatar');
        }

        final coverUrl = firestoreData?['coverUrl'] as String?;
        if (coverUrl != null && coverUrl.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(coverUrl));
            if (response.statusCode == 200) _realCover = response.bodyBytes;
          } catch (_) {}
        }
        if (_realCover == null && localData['hasCover'] == true) {
          _realCover = await _channel.invokeMethod<Uint8List>('getProfileCover');
        }
      } else {
        // USUARIO ANÓNIMO: Cargar solo de local
        _realName = (localData['name'] as String?) ?? '';
        _realBio = (localData['bio'] as String?) ?? '';
        if (localData['hasAvatar'] == true) {
          _realAvatar = await _channel.invokeMethod<Uint8List>('getProfileAvatar');
        }
        if (localData['hasCover'] == true) {
          _realCover = await _channel.invokeMethod<Uint8List>('getProfileCover');
        }
      }
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadVisitorProfile() async {
    setState(() => _loadingVisitorProfile = true);
    try {
      // Cargar perfil, packs y estado de seguimiento en paralelo
      final List<Future<dynamic>> futures = [
        _firestore.fetchUserProfile(widget.profileId),
        _firestore.fetchPacksByAuthor(widget.profileId),
      ];

      if (!_auth.isAnonymous && _auth.currentUid != null) {
        futures.add(
          _firestore.isFollowing(_auth.currentUid!, widget.profileId).catchError((_) => false),
        );
      }

      final results = await Future.wait(futures);

      final profileData = results[0] as Map<String, dynamic>?;
      final packsData = results[1] as List<Map<String, dynamic>>;
      if (results.length > 2) _isFollowing = results[2] as bool;

      if (profileData == null) {
        // El perfil no existe, no hay nada que mostrar.
        if (mounted) setState(() => _loadingVisitorProfile = false);
        return;
      }

      _visitorProfileData = profileData;
      _visitorPacks = packsData;

      // Cargar imágenes desde URLs
      final avatarUrl = profileData['avatarUrl'] as String?;
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(avatarUrl));
          if (response.statusCode == 200) _visitorAvatar = response.bodyBytes;
        } catch (_) {} // Ignorar errores de red
      }

      final coverUrl = profileData['coverUrl'] as String?;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        try {
          final response = await http.get(Uri.parse(coverUrl));
          if (response.statusCode == 200) _visitorCover = response.bodyBytes;
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _loadingVisitorProfile = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isTogglingFollow || _auth.isAnonymous || _auth.currentUid == null) return;

    setState(() => _isTogglingFollow = true);

    try {
      if (_isFollowing) {
        await _firestore.unfollowUser(_auth.currentUid!, widget.profileId);
        // Decrement local follower count for immediate UI update
        if (_visitorProfileData != null) {
          _visitorProfileData!['followersCount'] = (_visitorProfileData!['followersCount'] as int? ?? 0) - 1;
        }
      } else {
        await _firestore.followUser(_auth.currentUid!, widget.profileId);
        // Increment local follower count
        // Nota: El followingCount del *usuario actual* se actualiza en Firestore.
        // Aquí solo actualizamos el followersCount del *perfil visitado*.
        if (_visitorProfileData != null) {
          _visitorProfileData!['followersCount'] = (_visitorProfileData!['followersCount'] as int? ?? 0) + 1;
        }
      }
      setState(() => _isFollowing = !_isFollowing);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  Future<void> _loadRealPacks() async {
    setState(() => _loadingPacks = true);
    _realPacks.clear();
    _privatePacks.clear();

    try {
      if (_isOwner && !_auth.isAnonymous && _auth.currentUid != null) {
        // --- USUARIO AUTENTICADO ---
        // El problema es que al crear un pack, se guarda localmente y no en Firestore.
        // Como solución en la UI, cargamos los packs de AMBAS fuentes (local y Firestore)
        // y los unimos. Así, el usuario ve inmediatamente lo que crea.

        // 1. Cargar packs desde Firestore (la fuente de verdad en la nube).
        List<Map<String, dynamic>> firestorePacks = [];
        try {
          firestorePacks = await _firestore.fetchAllPacksByAuthor(_auth.currentUid!);
        } catch (e) {
          // Esto suele pasar si falta el índice compuesto en Firestore.
          // En lugar de crashear, mostramos un aviso y continuamos para
          // al menos mostrar los packs locales.
          debugPrint('Error al cargar packs de Firestore (probablemente falte un índice): $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se pudieron cargar los packs de la nube. Mostrando packs locales.')),
            );
          }
        }

        // 2. Cargar packs desde el almacenamiento local (donde se guardan erróneamente los nuevos).
        final jsonStr = await _channel.invokeMethod<String>('getStickerPacks');
        final List<dynamic> localList = jsonDecode(jsonStr ?? '[]');
        final localPacks = localList.cast<Map<String, dynamic>>().where((p) {
          return p['isDynamic'] == true && p['authorUid'] == _auth.currentUid;
        }).toList();

        // 3. Unir las dos listas, evitando duplicados.
        final allPacksMap = <String, Map<String, dynamic>>{};
        for (final pack in localPacks) {
          allPacksMap[pack['identifier'] as String] = pack;
        }
        for (final pack in firestorePacks) {
          allPacksMap[pack['identifier'] as String] = pack;
        }

        final allUserPacks = allPacksMap.values.toList();
        allUserPacks.sort((a, b) {
          final aTimestamp = a['createdAt'] as Timestamp?;
          final bTimestamp = b['createdAt'] as Timestamp?;
          if (aTimestamp == null && bTimestamp != null) return -1; // Locales (sin fecha) primero
          if (aTimestamp != null && bTimestamp == null) return 1;
          if (aTimestamp == null && bTimestamp == null) return 0;
          return bTimestamp!.compareTo(aTimestamp!); // Ordenar por fecha desc
        });

        _realPacks = allUserPacks;
        _privatePacks = allUserPacks.where((pack) {
          if (pack.containsKey('isPublic')) return pack['isPublic'] != true; // Firestore
          if (pack.containsKey('isPrivate')) return pack['isPrivate'] == true; // Local
          return false;
        }).toList();

        // Cargamos las vistas previas para cualquier pack en la lista final que no
        // tenga URLs remotas (es decir, que sea un pack local). Esto es clave para
        // que los packs recién creados (que solo existen localmente) aparezcan con
        // su preview.
        for (final pack in allUserPacks) {
          final id = pack['identifier'] as String;
          // Un pack es local si no tiene la clave 'isPublic' (que solo viene de Firestore).
          if (!pack.containsKey('isPublic') && !_realPreviewCache.containsKey(id)) {
            final stickers = await _channel.invokeListMethod<Uint8List>('getFirstNStickersForPack', {'identifier': id, 'count': 4});
            if (stickers != null) _realPreviewCache[id] = stickers.take(4).toList();
          }
        }
      } else {
        // Usuario anónimo: Cargar packs desde el almacenamiento local.
        final jsonStr = await _channel.invokeMethod<String>('getStickerPacks');
        final List<dynamic> list = jsonDecode(jsonStr ?? '[]');
        final allUserPacks = list.cast<Map<String, dynamic>>().where((p) {
          return p['isDynamic'] == true && p['authorUid'] == _auth.currentUid;
        }).toList();

        _realPacks = allUserPacks; // Mostrar todos (públicos y privados) en la pestaña principal.
        _privatePacks = allUserPacks.where((p) => p['isPrivate'] == true).toList();

        for (final pack in allUserPacks) {
          final id = pack['identifier'] as String;
          if (!_realPreviewCache.containsKey(id)) {
            final stickers = await _channel.invokeListMethod<Uint8List>('getFirstNStickersForPack', {'identifier': id, 'count': 4});
            if (stickers != null) _realPreviewCache[id] = stickers.take(4).toList();
          }
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

  Future<void> _handleSignIn() async {
    // This will trigger the authStateChanges listener in MainScreen,
    // which will rebuild the UI with the new user's profile.
    await _auth.linkWithGoogle();
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    // After this, authStateChanges() will fire in MainScreen, which will
    // replace this ProfileScreen with a new one for the anonymous user.
    await _auth.ensureSignedIn();
  }

  void _handleSettingsSelection(String value) {
    switch (value) {
      case 'login':
        _handleSignIn();
        break;
      case 'logout':
        _handleSignOut();
        break;
    }
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.push<EditProfileResult>(
      context,
      slideUpRoute(
        EditProfileScreen(
          currentName: _realName,
          username: _realUsername,
          currentBio: _realBio,
          currentAvatar: _realAvatar, // Pass current avatar bytes
          currentCover: _realCover, // Pass current cover bytes
        ),
      ),
    );
    if (result != null) {
      await _saveProfileCloud(result);
      _loadProfile();
      _loadFavorites(); // Nombres/etc. de packs favoritos pueden haber cambiado
    }
  }

  /// Guarda los datos del perfil en la nube (Firestore y Supabase) si hay sesión.
  Future<void> _saveProfileCloud(EditProfileResult result) async {
    if (_auth.isAnonymous || _auth.currentUid == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final uid = _auth.currentUid!;

    try {
      String? avatarUrl;
      String? coverUrl;

      // Subir imágenes a Supabase si han cambiado
      if (result.newAvatarBytes != null) {
        avatarUrl = await SupabaseStorageService.instance.uploadFile(
          path: '$uid/profile/avatar.png',
          bytes: result.newAvatarBytes!,
          contentType: 'image/png',
        );
      }
      if (result.newCoverBytes != null) {
        coverUrl = await SupabaseStorageService.instance.uploadFile(
          path: '$uid/profile/cover.png',
          bytes: result.newCoverBytes!,
          contentType: 'image/png',
        );
      }

      // Guardar URLs y datos en Firestore
      await _firestore.saveUserProfile(
          uid: uid, name: result.name, username: _realUsername, bio: result.bio, avatarUrl: avatarUrl, coverUrl: coverUrl);

      // Guardar también localmente para consistencia y uso offline
      await _channel.invokeMethod('saveProfile', {
        'name': result.name,
        'bio': result.bio,
        'avatarBytes': result.newAvatarBytes,
        'coverBytes': result.newCoverBytes,
      });
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error al sincronizar perfil con la nube: $e')));
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
    final isPrivate = pack['isPublic'] != true;

    // Si el pack viene de Firestore, tendrá URLs. Si es local, no.
    final stickerUrls = (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList();

    Navigator.push<bool>(
      context,
      slideUpRoute(
        CreatePackScreen(
          packName: name,
          // Para packs de Firestore, el autor es 'authorName'. Para locales, 'publisher'.
          publisher: (pack['authorName'] ?? publisher) as String,
          identifier: identifier,
          isEditing: true,
          isPrivate: isPrivate,
          initialStickerUrls: stickerUrls,
        ),
      ),
    ).then((refreshed) {
      if (refreshed == true) {
        _loadRealPacks();
        _loadFavorites();
      }
    });
  }

  void _openPublicPackPreview(Map<String, dynamic> pack) {
    final identifier = pack['identifier'] as String;
    // Increment views optimistically
    _firestore.incrementPackViews(identifier);

    Navigator.push(
      context,
      slideUpRoute(PackPreviewScreen(
        realIdentifier: identifier,
        packName: pack['name'] as String? ?? 'Sin nombre',
        publisherName: pack['authorName'] as String? ?? '',
        publisherId: pack['authorUid'] as String?,
        stickerCount: pack['stickerCount'] as int? ?? 0,
        isPrivate: (pack['isPublic'] as bool? ?? true) == false,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isOwner) {
      if (_loadingProfile) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    } else { // Visitor mode
      if (_loadingVisitorProfile) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_visitorProfileData == null) {
        return const Scaffold(body: Center(child: Text('Perfil no encontrado')));
      }
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
              if (_isOwner) // El menú de ajustes solo aparece en nuestro perfil
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Ajustes',
                  onSelected: _handleSettingsSelection,
                  itemBuilder: (context) {
                    if (_auth.isAnonymous) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'login',
                          child: Text('Iniciar sesión con Google'),
                        ),
                      ];
                    } else {
                      return [
                        const PopupMenuItem<String>(
                          value: 'logout',
                          child: Text('Cerrar sesión'),
                        ),
                      ];
                    }
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
                    fallbackColorA: myMockProfileHeader.bannerColorA, // Use myMockProfileHeader for fallback colors
                    fallbackColorB: myMockProfileHeader.bannerColorB, // Use myMockProfileHeader for fallback colors
                    isOwner: true,
                    following: _realFollowingCount,
                    packCount: _realPacks.length,
                    onEditTap: _openEditProfile,
                  )
                : _ProfileHeader(
                    name: _visitorProfileData!['name'] as String? ?? '',
                    handle: '@${_visitorProfileData!['username'] as String? ?? ''}',
                    bio: _visitorProfileData!['bio'] as String? ?? '',
                    verified: _visitorProfileData!['isVerified'] as bool? ?? false,
                    followers: _visitorProfileData!['followersCount'] as int? ?? 0,
                    avatarBytes: _visitorAvatar,
                    coverBytes: _visitorCover,
                    fallbackColorA: myMockProfileHeader.bannerColorA,
                    fallbackColorB: myMockProfileHeader.bannerColorB,
                    isOwner: false,
                    following: _visitorProfileData!['followingCount'] as int? ?? 0,
                    packCount: _visitorPacks.length,
                    onFollowTap: _toggleFollow,
                    isFollowing: _isFollowing,
                    isTogglingFollow: _isTogglingFollow,
                  ), // Close _ProfileHeader
          ),
          if (_isOwner)
            SliverToBoxAdapter(
              child: _ProfileTabs(selected: _profileTab, onChanged: (i) => setState(() => _profileTab = i)),
            ),
          if (_isOwner)
            ..._buildOwnerBodySlivers(colorScheme)
          else
            ..._buildVisitorBodySlivers(colorScheme),
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
                Icon(Icons.auto_awesome_rounded, size: 44, color: colorScheme.primary.withOpacity(0.35)),
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
              final stickerUrls = (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList();

              return _RealPackCard(
                pack: pack,
                // Si es un pack de Firestore, usamos URLs. Si es local, usamos el caché de bytes.
                previewStickerUrls: stickerUrls,
                previewStickers: _realPreviewCache[identifier],
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
                // Si es un pack de Firestore, usamos URLs. Si es local, usamos el caché de bytes.
                previewStickerUrls: (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList(),
                previewStickers: _realPreviewCache[pack['identifier'] as String],
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
                previewStickerUrls: (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList(),
                previewStickers: _realPreviewCache[identifier],
                onTap: () {
                  if (isDynamic) {
                    _openOwnedPack(pack);
                  } else {
                    // Para packs favoritos que no son dinámicos (p. ej. el de demo),
                    // intentamos ver si el creador es el usuario actual para poder navegar a su perfil.
                    // Es una heurística simple; un sistema real guardaría el ID del creador.
                    final publisher = pack['publisher'] as String? ?? '';
                     final publisherId =
                        (publisher.isNotEmpty && publisher == _realName) || (publisher.isEmpty) ? _auth.currentUid : null;
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

  List<Widget> _buildVisitorBodySlivers(ColorScheme colorScheme) {
    if (_loadingVisitorProfile) {
      return [
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    if (_visitorPacks.isEmpty) {
      return [
        const _PlaceholderTabSliver(
          icon: Icons.grid_off_rounded,
          title: 'Sin packs públicos',
          subtitle: 'Este creador aún no ha publicado ningún pack.',
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final pack = _visitorPacks[index];
              final stickerUrls = (pack['stickers'] as List?)?.map((s) => s['url'] as String).toList();
              return _RealPackCard(pack: pack, previewStickerUrls: stickerUrls, onTap: () => _openPublicPackPreview(pack));
            },
            childCount: _visitorPacks.length,
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
            Icon(icon, size: 44, color: colorScheme.primary.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), // Title for placeholder
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
  final int following;
  final Uint8List? avatarBytes;
  final Uint8List? coverBytes;
  final Color fallbackColorA;
  final Color fallbackColorB;
  final bool isOwner;
  final int packCount;
  final VoidCallback? onFollowTap;
  final VoidCallback? onEditTap;
  final bool isFollowing;
  final bool isTogglingFollow;

  const _ProfileHeader({
    required this.name,
    required this.handle,
    required this.bio,
    required this.verified,
    required this.following,
    required this.followers,
    required this.avatarBytes,
    required this.coverBytes,
    required this.fallbackColorA,
    required this.fallbackColorB,
    required this.isOwner,
    required this.packCount,
    this.onFollowTap,
    this.onEditTap,
    this.isFollowing = false,
    this.isTogglingFollow = false,
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
                    ? LinearGradient( // If no coverBytes, use gradient
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
                  backgroundColor: fallbackColorA.withOpacity(0.2),
                  backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes!) : null, // Display avatar image
                  child: avatarBytes == null ? Icon(Icons.person_rounded, size: 36, color: fallbackColorA) : null,
                ),
              ),
            ),
            if (!isOwner)
              Positioned(
                right: 16,
                bottom: -18,
                child: ElevatedButton(
                  onPressed: isTogglingFollow ? null : onFollowTap,
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: isFollowing ? Colors.grey.shade300 : null,
                    foregroundColor: isFollowing ? Colors.black : null,
                  ),
                  child: isTogglingFollow
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(isFollowing ? 'Siguiendo' : 'Seguir'),
                ),
              )
            else
              Positioned(
                right: 16,
                bottom: -18,
                child: OutlinedButton(
                  onPressed: onEditTap,
                  style: OutlinedButton.styleFrom( // Edit profile button for owner
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
                  Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), // Profile name
                  if (verified) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.verified_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
              Text(handle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              if (bio.isNotEmpty) ...[ // Display bio if not empty
                const SizedBox(height: 8),
                Text(bio, style: const TextStyle(fontSize: 13.5)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!isOwner) ...[
                    _StatChip(value: _formatCount(followers), label: 'Seguidores'),
                    const SizedBox(width: 18),
                    _StatChip(value: _formatCount(following), label: 'Siguiendo'),
                    const SizedBox(width: 18), // Spacing for follower count
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
  final List<Uint8List>? previewStickers;
  final List<String>? previewStickerUrls;
  final VoidCallback onTap;

  const _RealPackCard({
    required this.pack,
    this.previewStickers,
    this.previewStickerUrls,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Un pack puede venir de Firestore ('isPublic') o del almacenamiento local ('isPrivate').
    // Normalizamos esta lógica para que la tarjeta funcione con ambos.
    final bool isPublic;
    if (pack.containsKey('isPublic')) {
      isPublic = pack['isPublic'] as bool? ?? false;
    } else {
      isPublic = pack['isPrivate'] != true;
    }
    final stickerCount = pack['stickerCount'] as int? ?? 0;

    return _PackCardShell(
      onTap: onTap,
      title: pack['name'] as String,
      subtitle: '$stickerCount stickers',
      showLock: !isPublic,
      preview: StickerPreviewGrid(
        previewStickers: previewStickers,
        previewStickerUrls: previewStickerUrls,
      ),
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
      color: const Color(0xFFF3F1F8),
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
                padding: const EdgeInsets.all(10), // Padding for preview
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
                        Icon(Icons.lock_outline_rounded, size: 12, color: Colors.grey.shade500), // Lock icon for private packs
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

import 'package:cloud_firestore/cloud_firestore.dart';

/// Todo el acceso a las colecciones 'packs' y 'users' de Firestore pasa
/// por aquí, para no repetir nombres de colección/campos por toda la app.
class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _packs => _db.collection('packs');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  // ---------------- PACKS ----------------

  /// Publica (crea o actualiza) un pack público. [packId] es el mismo
  /// identifier que ya usas localmente, así queda enlazado 1 a 1 con tu
  /// pack en el dispositivo.
  Future<void> publishPack({
    required String packId,
    required String name,
    required String authorUid,
    required String authorName,
    String? authorAvatarUrl,
    required String trayUrl,
    required List<Map<String, dynamic>> stickers, // [{url, emojis}]
    bool isPublic = true,
  }) async {
    await _packs.doc(packId).set({
      'identifier': packId,
      'name': name,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorAvatarUrl': authorAvatarUrl,
      'trayUrl': trayUrl,
      'stickers': stickers,
      'stickerCount': stickers.length,
      'downloads': 0,
      'views': 0,
      'isPublic': isPublic,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deja de estar visible en el feed público (no borra el documento,
  /// por si luego el usuario lo quiere volver a publicar).
  Future<void> unpublishPack(String packId) async {
    await _packs.doc(packId).update({'isPublic': false});
  }

  /// Feed de Inicio: los packs públicos más recientes.
  Future<List<Map<String, dynamic>>> fetchFeedPacks({int limit = 30}) async {
    final snapshot = await _packs
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// Packs públicos de un autor específico (para su perfil visitado).
  Future<List<Map<String, dynamic>>> fetchPacksByAuthor(String authorUid) async {
    final snapshot = await _packs
        .where('authorUid', isEqualTo: authorUid)
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  /// Todos los packs (públicos y privados) de un autor.
  Future<List<Map<String, dynamic>>> fetchAllPacksByAuthor(String authorUid) async {
    final snapshot = await _packs
        .where('authorUid', isEqualTo: authorUid)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs.map((d) => d.data()).toList();
  }

  Future<Map<String, dynamic>?> fetchPack(String packId) async {
    final doc = await _packs.doc(packId).get();
    return doc.data();
  }

  Future<void> incrementPackViews(String packId) async {
    await _packs.doc(packId).update({'views': FieldValue.increment(1)});
  }

  Future<void> incrementPackDownloads(String packId) async {
    await _packs.doc(packId).update({'downloads': FieldValue.increment(1)});
  }

  // ---------------- USERS ----------------

  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String username,
    required String bio,
    String? avatarUrl,
    String? coverUrl,
    int? followersCount,
    int? followingCount,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'username': username,
      'bio': bio,
      'createdAt': FieldValue.serverTimestamp(),
    };
    // Solo añadimos las URLs al mapa si no son nulas, para no borrar
    // las existentes en la nube si el usuario solo cambia el texto.
    if (avatarUrl != null) data['avatarUrl'] = avatarUrl;
    if (coverUrl != null) data['coverUrl'] = coverUrl;
    if (followersCount != null) data['followersCount'] = followersCount;
    if (followingCount != null) data['followingCount'] = followingCount;

    await _users.doc(uid).set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.data();
  }

  Future<void> followUser(String currentUid, String targetUid) async {
    final batch = _db.batch();

    // Add target to current user's following subcollection
    final followingRef = _users.doc(currentUid).collection('following').doc(targetUid);
    batch.set(followingRef, {'followedAt': FieldValue.serverTimestamp()});

    // Add current user to target's followers subcollection
    final followerRef = _users.doc(targetUid).collection('followers').doc(currentUid);
    batch.set(followerRef, {'followedAt': FieldValue.serverTimestamp()});

    // Increment counts
    final currentUserDocRef = _users.doc(currentUid);
    batch.update(currentUserDocRef, {'followingCount': FieldValue.increment(1)});
    final targetUserDocRef = _users.doc(targetUid);
    batch.update(targetUserDocRef, {'followersCount': FieldValue.increment(1)});

    await batch.commit();
  }

  Future<void> unfollowUser(String currentUid, String targetUid) async {
    final batch = _db.batch();

    // Remove target from current user's following subcollection
    final followingRef = _users.doc(currentUid).collection('following').doc(targetUid);
    batch.delete(followingRef);

    // Remove current user from target's followers subcollection
    final followerRef = _users.doc(targetUid).collection('followers').doc(currentUid);
    batch.delete(followerRef);

    // Decrement counts
    final currentUserDocRef = _users.doc(currentUid);
    batch.update(currentUserDocRef, {'followingCount': FieldValue.increment(-1)});
    final targetUserDocRef = _users.doc(targetUid);
    batch.update(targetUserDocRef, {'followersCount': FieldValue.increment(-1)});

    await batch.commit();
  }

  Future<bool> isFollowing(String currentUid, String targetUid) async {
    if (currentUid.isEmpty || targetUid.isEmpty) return false;
    final followingDoc = await _users.doc(currentUid).collection('following').doc(targetUid).get();
    return followingDoc.exists;
  }

  Future<List<String>> getFollowingIds(String currentUid) async {
    final snapshot = await _users.doc(currentUid).collection('following').get();
    if (snapshot.docs.isEmpty) return [];
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  /// Feed de Creadores: los usuarios más recientes o con más seguidores.
  Future<List<Map<String, dynamic>>> fetchAllUsers({int limit = 50}) async {
    final snapshot = await _users
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['uid'] = doc.id; // Añadir el ID del documento como 'uid'
      return data;
    }).toList();
  }
}

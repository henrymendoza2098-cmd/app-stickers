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
      'isPublic': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
  }) async {
    await _users.doc(uid).set({
      'name': name,
      'username': username,
      'bio': bio,
      'avatarUrl': avatarUrl,
      'coverUrl': coverUrl,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.data();
  }
}

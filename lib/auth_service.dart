import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:whatsapp_stickers_app/firestore_service.dart';

/// Maneja el login. Estrategia: apenas se abre la app, si no hay sesión,
/// se crea una sesión anónima automáticamente (sin pedirle nada al
/// usuario). Más adelante, desde el perfil, el usuario puede "subir de
/// categoría" vinculando esa cuenta anónima con Google — así no pierde
/// sus packs ni su uid al iniciar sesión con Google.
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  /// The raw Firebase Auth instance, for listening to auth state changes.
  FirebaseAuth get auth => _auth;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  /// El uid actual. Nunca debería ser null después de [ensureSignedIn].
  String? get currentUid => _auth.currentUser?.uid;

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// Llamar una vez al arrancar la app (antes de runApp). Si ya hay una
  /// sesión (anónima o con Google) la reutiliza; si no, crea una nueva
  /// sesión anónima.
  Future<User> ensureSignedIn() async {
    final current = _auth.currentUser;
    if (current != null) return current;

    final credential = await _auth.signInAnonymously();
    if (credential.user == null) {
      throw Exception('No se pudo iniciar sesión anónima');
    }
    return credential.user!;
  }

  /// Vincula la sesión anónima actual con una cuenta de Google. Si el
  /// usuario ya tenía packs creados bajo el uid anónimo, se mantienen
  /// (el uid no cambia al vincular, solo "sube de categoría").
  /// Devuelve el usuario actualizado, o null si el usuario canceló el
  /// selector de cuentas de Google.
  Future<User?> linkWithGoogle() async {
    final googleUser = await _googleSignIn.authenticate();
    if (googleUser == null) return null; // el usuario canceló

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    User? finalUser;
    final current = _auth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        // Intenta vincular la cuenta anónima actual.
        // Esto funciona para usuarios nuevos que vinculan su cuenta por primera vez.
        final result = await current.linkWithCredential(credential);
        finalUser = result.user;
      } on FirebaseAuthException catch (e) {
        // Si falla porque la credencial ya está en uso, significa que es un usuario
        // que ya había iniciado sesión antes y ahora está volviendo.
        if (e.code == 'credential-already-in-use') {
          // En este caso, simplemente iniciamos sesión con esa credencial.
          // Esto descartará la sesión anónima actual y cargará la del usuario existente.
          finalUser = (await _auth.signInWithCredential(credential)).user;
        }
        // Si es otro tipo de error, lo relanzamos para que se maneje en la UI.
        else {
          rethrow;
        }
      }
    } else {
      // Ya no es anónimo (o no había sesión): inicia sesión normal.
      final result = await _auth.signInWithCredential(credential);
      finalUser = result.user;
    }

    // Después de vincular/iniciar sesión, crea un perfil en Firestore si no existe.
    // Esto asegura que todos los usuarios registrados sean visibles en el feed de creadores.
    if (finalUser != null) {
      final firestore = FirestoreService.instance;
      final existingProfile = await firestore.fetchUserProfile(finalUser.uid);
      if (existingProfile == null) {
        await firestore.saveUserProfile(
          uid: finalUser.uid,
          name: finalUser.displayName ?? 'Nuevo Creador',
          // Generamos un username a partir del email o uid como fallback.
          username: finalUser.email?.split('@').first ?? 'usuario_${finalUser.uid.substring(0, 6)}',
          bio: '',
          followersCount: 0,
          followingCount: 0,
        );
      }
    }
    return finalUser;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

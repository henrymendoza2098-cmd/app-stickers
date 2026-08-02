import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Maneja el login. Estrategia: apenas se abre la app, si no hay sesión,
/// se crea una sesión anónima automáticamente (sin pedirle nada al
/// usuario). Más adelante, desde el perfil, el usuario puede "subir de
/// categoría" vinculando esa cuenta anónima con Google — así no pierde
/// sus packs ni su uid al iniciar sesión con Google.
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
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

    final current = _auth.currentUser;
    if (current != null && current.isAnonymous) {
      // Vincula: conserva el mismo uid y todo lo que ya se creó con él.
      final result = await current.linkWithCredential(credential);
      return result.user;
    } else {
      // Ya no es anónimo (o no había sesión): inicia sesión normal.
      final result = await _auth.signInWithCredential(credential);
      return result.user;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

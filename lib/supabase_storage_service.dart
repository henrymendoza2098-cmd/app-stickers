import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Sube archivos al bucket público 'stickers' de Supabase usando la API
/// REST directamente (sin el paquete oficial de Supabase, para no sumar
/// otra dependencia pesada) y devuelve la URL pública final.
class SupabaseStorageService {
  static final SupabaseStorageService instance = SupabaseStorageService._();
  SupabaseStorageService._();

  // TODO: reemplaza estos dos valores con los tuyos
  // (Project Settings → API en tu dashboard de Supabase).
  // CORRECCIÓN: La URL del proyecto no debe incluir '/rest/v1' al final.
  static const String _projectUrl = 'https://sghxsmrvlvkdsiuaivvn.supabase.co';
  static const String _anonKey = 'sb_publishable_IYY66tY9rYt9Enw9TzlCfA_dBm4g28j';

  static const String _bucket = 'stickers';

  /// Sube un archivo y devuelve su URL pública.
  /// [path] es la ruta dentro del bucket, ej: 'uid123/pack456/tray.png'.
  Future<String> uploadFile({
    required String path,
    required Uint8List bytes,
    required String contentType, // 'image/png' o 'image/webp'
  }) async {
    final uri = Uri.parse('$_projectUrl/storage/v1/object/$_bucket/$path'); // La URL correcta es '.../storage/v1/...'

    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $_anonKey',
        'apikey': _anonKey,
        'Content-Type': contentType,
        'x-upsert': 'true', // permite sobrescribir si ya existía
      },
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Error subiendo a Supabase (${response.statusCode}): ${response.body}');
    }

    return publicUrlFor(path);
  }

  /// Construye la URL pública de un archivo sin necesidad de subirlo
  /// (útil para saber de antemano dónde va a quedar).
  String publicUrlFor(String path) {
    return '$_projectUrl/storage/v1/object/public/$_bucket/$path'; // La URL pública también usa '.../storage/v1/...'
  }

  /// Sube el tray + todos los stickers de un pack de una sola vez.
  /// Devuelve un mapa { 'trayUrl': ..., 'stickerUrls': [...] } en el
  /// mismo orden que [stickers].
  Future<PackUploadResult> uploadPack({
    required String authorUid,
    required String packId,
    required Uint8List trayBytes,
    required List<Uint8List> stickerBytes,
  }) async {
    final basePath = '$authorUid/$packId';

    final trayUrl = await uploadFile(
      path: '$basePath/tray.png',
      bytes: trayBytes,
      contentType: 'image/png',
    );

    final stickerUrls = <String>[];
    for (var i = 0; i < stickerBytes.length; i++) {
      final url = await uploadFile(
        path: '$basePath/sticker_${i + 1}.webp',
        bytes: stickerBytes[i],
        contentType: 'image/webp',
      );
      stickerUrls.add(url);
    }

    return PackUploadResult(trayUrl: trayUrl, stickerUrls: stickerUrls);
  }
}

class PackUploadResult {
  final String trayUrl;
  final List<String> stickerUrls;
  PackUploadResult({required this.trayUrl, required this.stickerUrls});
}

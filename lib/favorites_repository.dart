import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Un repositorio simple basado en archivos para almacenar los packs de stickers favoritos.
///
/// Guarda una lista de mapas de packs en un archivo JSON en el directorio
/// de documentos de la aplicación.
///
/// NOTA: Para que esto funcione, asegúrate de agregar `path_provider` a tu
/// archivo `pubspec.yaml`.
class FavoritesRepository {
  static const _fileName = 'favorites.json';
  static List<Map<String, dynamic>>? _cache;

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    if (_cache != null) return List.from(_cache!);
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        return [];
      }
      final contents = await file.readAsString();
      if (contents.isEmpty) {
        return [];
      }
      final List<dynamic> json = jsonDecode(contents);
      _cache = json.cast<Map<String, dynamic>>();
      return List.from(_cache!);
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveFavorites(List<Map<String, dynamic>> favorites) async {
    _cache = favorites;
    final file = await _localFile;
    await file.writeAsString(jsonEncode(favorites));
  }

  Future<void> addFavorite(Map<String, dynamic> pack) async {
    final favorites = await getFavorites();
    if (!favorites.any((p) => p['identifier'] == pack['identifier'])) {
      favorites.add(pack);
      await _saveFavorites(favorites);
    }
  }

  Future<void> removeFavorite(String identifier) async {
    final favorites = await getFavorites();
    favorites.removeWhere((p) => p['identifier'] == identifier);
    await _saveFavorites(favorites);
  }
}
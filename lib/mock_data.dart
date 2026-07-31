import 'package:flutter/material.dart';

/// ID del usuario que tiene la sesión activa "ahora mismo" en la app.
/// Como todavía no hay backend/login real, este valor fijo hace de
/// stand-in — cuando conectes autenticación real, esto vendría de tu
/// sistema de sesión en vez de ser una constante.
const String currentUserId = 'me';

/// Un pack tal como se muestra en el perfil (ya sea real o simulado).
class MockPack {
  final String id;
  final String name;
  final int stickerCount;
  final int downloads;
  final bool isPublic; // false = privado / borrador
  final IconData previewIcon;
  final Color previewColor;

  const MockPack({
    required this.id,
    required this.name,
    required this.stickerCount,
    required this.downloads,
    required this.isPublic,
    required this.previewIcon,
    required this.previewColor,
  });
}

/// Perfil de un creador (visitante). El perfil del usuario dueño de la
/// sesión ("me") no usa esta lista para sus packs (esos se leen de tus
/// datos reales) — pero sí para el nombre/avatar/bio de portada.
class MockProfile {
  final String id;
  final String name;
  final String handle;
  final String bio;
  final int followers;
  final bool verified;
  final Color bannerColorA;
  final Color bannerColorB;
  final List<MockPack> packs;

  const MockProfile({
    required this.id,
    required this.name,
    required this.handle,
    required this.bio,
    required this.followers,
    required this.verified,
    required this.bannerColorA,
    required this.bannerColorB,
    this.packs = const [],
  });
}

/// Perfil "propio" — solo para portada (nombre/avatar/bio). Sus packs
/// reales se cargan desde el almacenamiento nativo, no de aquí.
const MockProfile myMockProfileHeader = MockProfile(
  id: currentUserId,
  name: 'Tú',
  handle: '@mis_stickers',
  bio: 'Mis packs de stickers 🎨',
  followers: 0,
  verified: false,
  bannerColorA: Color(0xFF6C5CE7),
  bannerColorB: Color(0xFFFF7A59),
);

/// Un creador de ejemplo, 100% simulado, para poder probar el
/// "modo visitante" sin necesidad de un backend real.
final MockProfile demoVisitorProfile = MockProfile(
  id: 'creator_demo',
  name: 'Geysioy Stickers',
  handle: '@geysioystickers',
  bio: '💖✨ Con amor para tú 🥺',
  followers: 107800,
  verified: true,
  bannerColorA: const Color(0xFFFFC93C),
  bannerColorB: const Color(0xFF6C5CE7),
  packs: const [
    MockPack(
      id: 'demo_1',
      name: 'Ramos para ti amor 💐❤️',
      stickerCount: 30,
      downloads: 10900,
      isPublic: true,
      previewIcon: Icons.local_florist_rounded,
      previewColor: Color(0xFFFF7A9C),
    ),
    MockPack(
      id: 'demo_2',
      name: 'Emojis animados con estilo',
      stickerCount: 27,
      downloads: 284200,
      isPublic: true,
      previewIcon: Icons.emoji_emotions_rounded,
      previewColor: Color(0xFFFFC93C),
    ),
    MockPack(
      id: 'demo_3',
      name: 'Rojo o azul 2 🔥',
      stickerCount: 30,
      downloads: 168,
      isPublic: true,
      previewIcon: Icons.favorite_rounded,
      previewColor: Color(0xFFFF5555),
    ),
    // Este pack es privado/borrador a propósito: sirve para comprobar
    // que el modo visitante lo oculta y el modo dueño sí lo vería.
    MockPack(
      id: 'demo_4',
      name: 'Borrador sin publicar',
      stickerCount: 5,
      downloads: 0,
      isPublic: false,
      previewIcon: Icons.edit_note_rounded,
      previewColor: Colors.grey,
    ),
  ],
);

/// Busca un perfil simulado por id (solo el visitante demo, por ahora).
MockProfile? findMockProfile(String id) {
  if (id == demoVisitorProfile.id) return demoVisitorProfile;
  return null;
}

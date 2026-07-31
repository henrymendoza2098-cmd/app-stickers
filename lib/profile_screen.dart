import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'create_pack_screen.dart';
import 'page_transitions.dart';

// --- Mock Data (Simulación de Backend) ---

const String currentUserId = 'user_henry'; // ID del usuario con sesión activa

class MockUser {
  final String id;
  final String name;
  final String avatarUrl;
  const MockUser({required this.id, required this.name, required this.avatarUrl});
}

class MockStickerPack {
  final String id;
  final String name;
  final int stickerCount;
  final bool isPublic;
  final List<String> stickerThumbnails; // Usaremos placeholders por ahora

  const MockStickerPack({
    required this.id,
    required this.name,
    required this.stickerCount,
    this.isPublic = true,
    required this.stickerThumbnails,
  });
}

const userHenry = MockUser(id: 'user_henry', name: 'Henry', avatarUrl: 'https://i.pravatar.cc/150?u=henry');
const userAna = MockUser(id: 'user_ana', name: 'Ana', avatarUrl: 'https://i.pravatar.cc/150?u=ana');

final Map<String, List<MockStickerPack>> mockPacksByUser = {
  'user_henry': [
    const MockStickerPack(id: 'p1', name: 'Mis Memes', stickerCount: 12, stickerThumbnails: ['t1', 't2', 't3', 't4']),
    const MockStickerPack(id: 'p2', name: 'Gatos', stickerCount: 21, stickerThumbnails: ['t1', 't2', 't3']),
    const MockStickerPack(id: 'p3', name: 'Borrador Secreto', stickerCount: 5, isPublic: false, stickerThumbnails: ['t1', 't2']),
  ],
  'user_ana': [
    const MockStickerPack(id: 'p4', name: 'Frases de Ana', stickerCount: 18, stickerThumbnails: ['t1', 't2', 't3', 't4']),
    const MockStickerPack(id: 'p5', name: 'Viajes por el Mundo', stickerCount: 30, stickerThumbnails: ['t1', 't2', 't3']),
    const MockStickerPack(id: 'p6', name: 'Recetas (privado)', stickerCount: 9, isPublic: false, stickerThumbnails: ['t1']),
  ],
};

// --- Fin de Mock Data ---

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();

  static void showAsVisitor(BuildContext context, String userId) {
    Navigator.push(context, slideUpRoute(ProfileScreen(userId: userId)));
  }
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final bool _isMe;
  late final MockUser _user;
  late final List<MockStickerPack> _packs;

  @override
  void initState() {
    super.initState();
    // Lógica de control: determinar el modo de visualización
    _isMe = widget.userId == currentUserId;
    _user = widget.userId == 'user_henry' ? userHenry : userAna;

    // Filtrar packs según el modo
    final allPacks = mockPacksByUser[widget.userId] ?? [];
    _packs = _isMe ? allPacks : allPacks.where((pack) => pack.isPublic).toList();
  }

  void _onPackTap(MockStickerPack pack) {
    if (_isMe) {
      // Modo Personal: Navegar a la pantalla de edición
      Navigator.push(
        context,
        slideUpRoute(
          CreatePackScreen(
            isEditing: true,
            packName: pack.name,
            publisher: _user.name,
            identifier: pack.id,
          ),
        ),
      );
    } else {
      // Modo Visitante: Navegar a la vista previa pública (simulado)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Navegando a la vista previa de "${pack.name}"...')),
      );
    }
  }

  void _createNewPack() {
    Navigator.push(context, slideUpRoute(const CreatePackScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(backgroundImage: NetworkImage(_user.avatarUrl)),
            const SizedBox(width: 12),
            Text(_user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // Elemento visible solo en Modo Personal
          if (_isMe)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                // TODO: Navegar a la pantalla de ajustes del perfil
              },
            ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.75,
        ),
        itemCount: _packs.length,
        itemBuilder: (context, index) {
          final pack = _packs[index];
          return _PackCard(
            pack: pack,
            onTap: () => _onPackTap(pack),
          );
        },
      ),
      // Elemento visible solo en Modo Personal
      floatingActionButton: _isMe
          ? FloatingActionButton(
              onPressed: _createNewPack,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _PackCard extends StatelessWidget {
  final MockStickerPack pack;
  final VoidCallback onTap;

  const _PackCard({required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bloque de vista previa de stickers
            Expanded(
              child: Container(
                width: double.infinity,
                color: colorScheme.primary.withOpacity(0.08),
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    pack.stickerThumbnails.length > 4 ? 4 : pack.stickerThumbnails.length,
                    (index) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          // Placeholder para las miniaturas
                          child: Icon(Icons.image_rounded, color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Información del paquete
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pack.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!pack.isPublic) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.lock, size: 12, color: Colors.grey.shade600),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pack.stickerCount} stickers',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
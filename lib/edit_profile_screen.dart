import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:whatsapp_stickers_app/profile_screen.dart';
import 'crop_screen.dart';
import 'page_transitions.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentName;
  final String username;
  final String currentBio;
  final Uint8List? currentAvatar;
  final Uint8List? currentCover;

  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.username,
    required this.currentBio,
    this.currentAvatar,
    this.currentCover, 
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
    static const _channel = MethodChannel('whatsapp_stickers_channel');
  late final TextEditingController _nameController;
    late final TextEditingController _bioController;

  Uint8List? _avatar;
  Uint8List? _cover;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName); // Initialize name controller
    _bioController = TextEditingController(text: widget.currentBio); // Initialize bio controller
    _avatar = widget.currentAvatar; // Set initial avatar
    _cover = widget.currentCover; // Set initial cover
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose(); // Dispose bio controller
    super.dispose();
  }

  // La foto principal (avatar) se recorta cuadrada, igual que un sticker,
  // reutilizando la misma pantalla de recorte que ya tienes.
  Future<void> _pickAvatar() async {
    final Uint8List? original = await _channel.invokeMethod<Uint8List>('pickImage');
    if (original == null || !mounted) return;
    final cropped = await Navigator.push<Uint8List>(context, slideUpRoute(CropScreen(imageBytes: original)));
    if (cropped == null) return;
    setState(() => _avatar = cropped);
  }

  // La portada no se recorta (se ve completa, tipo banner ancho).
  Future<void> _pickCover() async {
    final Uint8List? original = await _channel.invokeMethod<Uint8List>('pickImage');
    if (original == null || !mounted) return;
    setState(() => _cover = original);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Construimos el resultado para devolverlo a ProfileScreen
      final result = EditProfileResult(
        name: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        newAvatarBytes: !identical(_avatar, widget.currentAvatar) ? _avatar : null,
        newCoverBytes: !identical(_cover, widget.currentCover) ? _cover : null,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Foto de portada', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickCover,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration( // Decoration for cover photo
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.primary.withValues(alpha: 0.08),
                image: _cover != null ? DecorationImage(image: MemoryImage(_cover!), fit: BoxFit.cover) : null,
              ),
              child: Stack(
                children: [
                  if (_cover == null)
                    Center(
                      child: Icon(Icons.add_photo_alternate_rounded, color: colorScheme.primary, size: 32),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.black54,
                      child: Icon(_cover == null ? Icons.add : Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Text('Foto de perfil', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48, // Radius for avatar
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                    backgroundImage: _avatar != null ? MemoryImage(_avatar!) : null,
                    child: _avatar == null ? Icon(Icons.person_rounded, size: 44, color: colorScheme.primary) : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: colorScheme.primary,
                      child: const Icon(Icons.edit, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Text('Nombre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'Tu nombre'),
          ),
          const SizedBox(height: 22),
          const Text('Biografía', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Cuéntanos sobre ti...'),
          ),
          const SizedBox(height: 22),
          const Text('Nombre de usuario', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('@${widget.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade500),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'El nombre de usuario lo asigna la app automáticamente y no se puede cambiar.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

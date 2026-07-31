import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'create_pack_screen.dart';
import 'crop_screen.dart';
import 'gallery_screen.dart';
import 'page_transitions.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const _channel = MethodChannel('whatsapp_stickers_channel');
  final GlobalKey<GalleryScreenState> _galleryKey = GlobalKey<GalleryScreenState>();
  int _selectedIndex = 0;

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      GalleryScreen(key: _galleryKey),
      const ProfileScreen(userId: currentUserId),
    ];
  }

  void _refreshGallery() {
    _galleryKey.currentState?.loadPacks();
  }
  
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
          body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).bottomAppBarTheme.color,
        elevation: 10,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Inicio',
                selected: _selectedIndex == 0,
                color: colorScheme.primary,
                onTap: () => _onItemTapped(0),
              ),
              _CentralAddButton(color: colorScheme.primary, onTap: _onAddStickerTapped),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'Perfil',
                selected: _selectedIndex == 1,
                color: colorScheme.primary,
                onTap: () => _onItemTapped(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAddStickerTapped() async {
    final Uint8List? original = await _channel.invokeMethod<Uint8List>('pickImage');
    if (original == null || !mounted) return;

    final cropped = await Navigator.push<Uint8List>(
      context,
      slideUpRoute(CropScreen(imageBytes: original)),
    );
    if (cropped == null || !mounted) return;

    _showSaveStickerSheet(cropped);
  }

  void _showSaveStickerSheet(Uint8List newSticker) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _SaveStickerSheet(
        newSticker: newSticker,
        channel: _channel,
        onStickerSaved: () {
          _refreshGallery();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Sticker guardado con éxito! ✅')),
          );
        },
      ),
    );
  }
}

class _CentralAddButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _CentralAddButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Theme.of(context).iconTheme.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : inactiveColor, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel inferior para elegir a qué pack guardar un sticker nuevo.
class _SaveStickerSheet extends StatefulWidget {
  final Uint8List newSticker;
  final MethodChannel channel;
  final VoidCallback onStickerSaved;

  const _SaveStickerSheet({required this.newSticker, required this.channel, required this.onStickerSaved});

  @override
  State<_SaveStickerSheet> createState() => _SaveStickerSheetState();
}

class _SaveStickerSheetState extends State<_SaveStickerSheet> {
  List<Map<String, dynamic>> _packs = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadUserPacks();
  }

  Future<void> _loadUserPacks() async {
    setState(() => _loading = true);
    final jsonStr = await widget.channel.invokeMethod<String>('getStickerPacks');
    final List<dynamic> allPacks = jsonDecode(jsonStr ?? '[]');
    if (mounted) {
      setState(() {
        _packs = allPacks.cast<Map<String, dynamic>>().where((p) => p['isDynamic'] == true).toList();
        _loading = false;
      });
    }
  }

  Future<void> _addStickerToPack(String identifier) async {
    setState(() => _saving = true);
    try {
      await widget.channel.invokeMethod('addStickerToPack', {
        'identifier': identifier,
        'stickerBytes': widget.newSticker,
        'emojis': ['😀'],
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onStickerSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  void _createNewPack() {
    Navigator.pop(context);
    Navigator.push(
      context,
      slideUpRoute(CreatePackScreen(initialStickers: [widget.newSticker])),
    ).then((saved) {
      if (saved == true) widget.onStickerSaved();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ... (El resto del código de _SaveStickerSheet se mantiene igual, lo he omitido por brevedad)
    // ... pero en el código real, todo el `build` de _SaveStickerSheet iría aquí.
    // Esta es una simplificación para la respuesta.
    return Container(); // Placeholder
  }
}
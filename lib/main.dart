import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'main_screen.dart';


void main() {
  runApp(const StickerApp());
}

class StickerApp extends StatelessWidget {
  const StickerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mis Stickers',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

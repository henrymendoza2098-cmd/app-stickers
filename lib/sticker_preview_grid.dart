import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Grid de preview para los stickers en la tarjeta del pack.
class StickerPreviewGrid extends StatelessWidget {
  final List<Uint8List>? previewStickers;
  final List<String>? previewStickerUrls;
  final int crossAxisCount;

  const StickerPreviewGrid({super.key, this.previewStickers, this.previewStickerUrls});
  const StickerPreviewGrid({
    super.key,
    this.previewStickers,
    this.previewStickerUrls,
    this.crossAxisCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if ((previewStickerUrls == null || previewStickerUrls!.isEmpty) &&
        (previewStickers == null || previewStickers!.isEmpty)) {
      return const Center(child: Text('No hay stickers para mostrar'));
    }

    return Builder(
      builder: (context) {
        final hasLocalStickers = previewStickers != null && previewStickers!.isNotEmpty;
        final hasRemoteStickers = previewStickerUrls != null && previewStickerUrls!.isNotEmpty;
    final itemCount = previewStickerUrls?.length ?? previewStickers?.length ?? 0;

        if (!hasLocalStickers && !hasRemoteStickers) {
          return Center(child: Icon(Icons.image_rounded, size: 48, color: colorScheme.primary.withOpacity(0.35)));
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        Widget image;
        if (previewStickerUrls != null && previewStickerUrls!.isNotEmpty) {
          image = Image.network(
            previewStickerUrls![index],
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            },
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.error_outline, color: Colors.grey);
            },
          );
        } else {
          image = Image.memory(previewStickers![index], fit: BoxFit.contain);
        }

        // Estilo de cuadrícula minimalista
        final itemCount = hasLocalStickers ? previewStickers!.take(4).length : previewStickerUrls!.take(4).length;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final image = hasLocalStickers
                ? Image.memory(previewStickers![index], fit: BoxFit.contain)
                : Image.network(
                    previewStickerUrls![index],
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                  );
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image,
            );
          },
          child: image,
        );
      },
    );
  }
}
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/private_image_store.dart';
import '../../icons/icon_catalog.dart';
import '../../models/config.dart';

class ButtonFace extends StatelessWidget {
  const ButtonFace({
    super.key,
    required this.button,
    required this.imageStore,
    this.pressed = false,
    this.editing = false,
    this.shortcutLabel,
  });

  final ButtonConfig button;
  final PrivateImageStore imageStore;
  final bool pressed;
  final bool editing;
  final String? shortcutLabel;

  @override
  Widget build(BuildContext context) {
    final displayedShortcut = shortcutLabel ?? button.subtitle;
    final colorScheme = Theme.of(context).colorScheme;
    final background = button.visual.backgroundColor == null
        ? (pressed ? colorScheme.primaryContainer : const Color(0xFF151E2A))
        : Color(button.visual.backgroundColor!);
    final foreground = button.visual.tintColor == null
        ? (pressed ? colorScheme.onPrimaryContainer : colorScheme.onSurface)
        : Color(button.visual.tintColor!);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: editing ? colorScheme.tertiary : const Color(0xFF263244),
          width: editing ? 2 : 1,
        ),
        boxShadow: pressed
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      transform: pressed
          ? (Matrix4.identity()..scaleByDouble(0.97, 0.97, 1, 1))
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (button.visual.type == VisualType.customImage)
              _PrivateImage(
                relativePath: button.visual.value,
                fit: button.visual.fit,
                scale: button.visual.imageScale,
                alignment: Alignment(
                  button.visual.alignmentX,
                  button.visual.alignmentY,
                ),
                imageStore: imageStore,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (button.visual.type == VisualType.builtinIcon)
                    Flexible(
                      child: Icon(
                        BuiltinIconCatalog.find(button.visual.value)?.icon ??
                            Icons.extension_off_outlined,
                        size: button.visual.iconSize,
                        color: foreground,
                      ),
                    ),
                  if (button.showLabel && button.label.isNotEmpty) ...[
                    if (button.visual.type != VisualType.none)
                      const SizedBox(height: 3),
                    Text(
                      button.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: button.textSize,
                        fontWeight: FontWeight.w600,
                        shadows: button.visual.type == VisualType.customImage
                            ? const [Shadow(color: Colors.black, blurRadius: 5)]
                            : null,
                      ),
                    ),
                  ],
                  if (button.showShortcut && displayedShortcut.isNotEmpty)
                    Text(
                      displayedShortcut,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.72),
                        fontSize: 10,
                        shadows: button.visual.type == VisualType.customImage
                            ? const [Shadow(color: Colors.black, blurRadius: 4)]
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (editing)
              const Positioned(
                top: 5,
                right: 5,
                child: Icon(Icons.edit, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrivateImage extends StatelessWidget {
  const _PrivateImage({
    required this.relativePath,
    required this.fit,
    required this.scale,
    required this.imageStore,
    required this.alignment,
  });

  final String? relativePath;
  final VisualFit fit;
  final double scale;
  final PrivateImageStore imageStore;
  final Alignment alignment;

  BoxFit get boxFit => switch (fit) {
    VisualFit.contain => BoxFit.contain,
    VisualFit.cover || VisualFit.centerCrop => BoxFit.cover,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: imageStore.resolve(relativePath),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return Container(
            key: const ValueKey('missing-image-placeholder'),
            color: const Color(0xFF222A35),
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
            ),
          );
        }
        return Transform.scale(
          scale: scale,
          child: Image.file(file, fit: boxFit, alignment: alignment),
        );
      },
    );
  }
}

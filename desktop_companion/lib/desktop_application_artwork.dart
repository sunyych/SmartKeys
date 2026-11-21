import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'app_icon_service.dart';
import 'icons/builtin_icon_catalog.g.dart';

/// Generated product artwork never expands the native command allowlist.
final desktopAppIconAssets = <String, String>{
  for (final icon in builtinIconCatalog) icon.id: '${icon.id}.png',
};

class DesktopApplicationArtwork extends StatefulWidget {
  const DesktopApplicationArtwork({
    super.key,
    required this.app,
    required this.size,
    this.iconService,
  });
  final RemoteApplication app;
  final double size;
  final NativeAppIconService? iconService;
  @override
  State<DesktopApplicationArtwork> createState() =>
      _DesktopApplicationArtworkState();
}

class _DesktopApplicationArtworkState extends State<DesktopApplicationArtwork> {
  static final _nativeService = NativeAppIconService();
  late Future<Uint8List?> _icon;
  void _load() {
    _icon = _catalogAsset != null
        ? Future.value()
        : widget.app.detected
        ? (widget.iconService ?? _nativeService).getNativeIcon(widget.app)
        : Future.value();
  }

  String? get _catalogAsset =>
      desktopAppIconAssets[canonicalBuiltinIconId(
            legacyProtocolIconId(widget.app.id),
          ) ??
          canonicalBuiltinIconId(widget.app.icon)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DesktopApplicationArtwork old) {
    super.didUpdateWidget(old);
    if (old.app.id != widget.app.id ||
        old.app.icon != widget.app.icon ||
        old.app.executable != widget.app.executable ||
        old.app.detected != widget.app.detected ||
        old.iconService != widget.iconService) {
      _load();
    }
  }

  Widget _fallback() {
    final file = _catalogAsset;
    final missing = Icon(Icons.apps, size: widget.size);
    return file == null
        ? missing
        : Image.asset(
            'assets/app_icons/$file',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            semanticLabel: '${widget.app.name} icon',
            errorBuilder: (_, _, _) => missing,
          );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    key: ValueKey((
      widget.app.id,
      widget.app.executable,
      widget.app.detected,
      widget.app.icon,
      widget.iconService,
    )),
    future: _icon,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      return bytes == null
          ? _fallback()
          : Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _fallback(),
            );
    },
  );
}

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'app_icon_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_library/app_library.dart';
import 'app_library_bundle.dart';
import 'desktop_controller.dart';
import 'icons/builtin_icon_catalog.g.dart';

class DesktopAppLibraryPage extends StatefulWidget {
  const DesktopAppLibraryPage({super.key, required this.controller});
  final DesktopController controller;
  @override
  State<DesktopAppLibraryPage> createState() => _DesktopAppLibraryPageState();
}

class _DesktopAppLibraryPageState extends State<DesktopAppLibraryPage> {
  late String os = widget.controller.libraryOperatingSystem;
  String query = '';
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Widget _artwork(AppLibraryApp app, {AppLibraryBundle? bundle}) {
    final profile = widget.controller.manifest.profiles
        .where((p) => p.sourceAppId == app.id && p.sourceIconPngBase64 != null)
        .firstOrNull;
    final bytes =
        bundle?.pngBytes ??
        (profile == null ? null : desktopLibraryProfileIcon(profile));
    if (bytes != null) {
      return Image.memory(bytes, width: 44, height: 44, fit: BoxFit.contain);
    }
    final icon = builtinIconById(app.iconId);
    return icon == null
        ? const Icon(Icons.apps, size: 44)
        : Image.asset(icon.assetPath, width: 44, height: 44);
  }

  Future<void> importBundle() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      if (result == null || !mounted) return;
      final selected = result.files.single;
      if (selected.size > AppLibraryBundle.maxBytes || selected.path == null) {
        throw const FormatException('App bundle is too large or unreadable');
      }
      final bytes = <int>[];
      await for (final chunk in File(selected.path!).openRead()) {
        if (bytes.length + chunk.length > AppLibraryBundle.maxBytes) {
          throw const FormatException('App bundle exceeds its size limit');
        }
        bytes.addAll(chunk);
      }
      final bundle = AppLibraryBundle.decode(bytes);
      if (!mounted) return;
      final library = bundle.app.libraryForOS(
        widget.controller.libraryOperatingSystem,
      );
      if (library == null) {
        throw const FormatException(
          'This App is not available for this computer OS',
        );
      }
      await preview(bundle.app, bundle: bundle);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not import this App bundle. Check its catalog version, icon and supported computer OS.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> preview(AppLibraryApp app, {AppLibraryBundle? bundle}) async {
    final targetOS = bundle == null
        ? os
        : widget.controller.libraryOperatingSystem;
    final library = app.libraryForOS(targetOS);
    if (library == null) return;
    String? replace;
    String? feedback;
    bool saving = false;
    final existing = widget.controller.manifest.profiles
        .where((p) => p.sourceAppId == app.id && p.platform == targetOS)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, state) => AlertDialog(
          key: const ValueKey('desktop-app-library-preview'),
          scrollable: true,
          title: Text('${app.name} · ${appLibraryOSLabel(targetOS)}'),
          content: SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${appLibraryContextLabel(library.context)} · v${library.version}',
                ),
                const SizedBox(height: 10),
                for (final action in library.actions)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(action.title),
                    subtitle: Text(
                      action.isConfigured
                          ? formatAppLibraryChord(action.keys, targetOS)
                          : 'Unassigned · configure before use',
                    ),
                  ),
                const Text('Sources'),
                for (final url in library.sourceUrls) SelectableText(url),
                const SizedBox(height: 10),
                const Text(
                  'Adds an icon and keyboard profile. No app executable, private launch combination or Launchpad slot is changed. For manual profiles, focus the intended app before sending keys.',
                ),
                if (targetOS != widget.controller.libraryOperatingSystem)
                  const Text(
                    'Preview only: installation must use this computer’s actual OS.',
                  ),
                if (existing.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('desktop-library-replacement'),
                    initialValue: '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Installation',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Add a new copy (default)'),
                      ),
                      for (final p in existing)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            'Replace ${p.name} · retain custom edits',
                          ),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (id) => state(() => replace = id == '' ? null : id),
                  ),
                if (feedback != null)
                  Text(
                    feedback!,
                    key: const ValueKey('desktop-library-result'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              key: const ValueKey('desktop-library-install'),
              onPressed:
                  saving ||
                      (!app.bundled &&
                          bundle == null &&
                          !existing.any(
                            (p) => p.sourceIconPngBase64 != null,
                          )) ||
                      targetOS != widget.controller.libraryOperatingSystem
                  ? null
                  : () async {
                      state(() {
                        saving = true;
                        feedback = null;
                      });
                      try {
                        await widget.controller.installAppLibrary(
                          app.id,
                          library.id,
                          replaceProfileId: replace,
                          bundle: bundle,
                        );
                        if (context.mounted) {
                          state(() {
                            saving = false;
                            feedback =
                                'App icon and shortcuts saved. Manage its visibility in Apps → Phone sidebar.';
                          });
                        }
                      } catch (_) {
                        if (context.mounted) {
                          state(() {
                            saving = false;
                            feedback =
                                'Could not save. Previous settings remain available; retry or add a copy.';
                          });
                        }
                      }
                    },
              child: Text(
                replace == null
                    ? 'Add icon + shortcuts'
                    : 'Replace · retain custom edits',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = AppLibraryCatalog.builtin.apps
        .where(
          (app) =>
              app.libraryForOS(os) != null &&
              [app.id, app.name, ...app.aliases].any(
                (name) =>
                    name.toLowerCase().contains(query.trim().toLowerCase()),
              ),
        )
        .toList();
    return Scaffold(
      key: const ValueKey('app-library-catalog'),
      appBar: AppBar(title: const Text('App library')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('desktop-library-search'),
                    decoration: const InputDecoration(
                      labelText: 'Search App name or ID',
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('desktop-library-os'),
                    initialValue: os,
                    decoration: const InputDecoration(
                      labelText: 'Preview computer OS',
                    ),
                    items: [
                      for (final value in const ['macos', 'windows', 'linux'])
                        DropdownMenuItem(
                          value: value,
                          child: Text(appLibraryOSLabel(value)),
                        ),
                    ],
                    onChanged: (value) => setState(() => os = value!),
                  ),
                  Text(
                    'This computer: ${appLibraryOSLabel(widget.controller.libraryOperatingSystem)}. Other systems are preview-only.',
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('desktop-library-import'),
                    onPressed: busy ? null : importBundle,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Import reviewed App bundle'),
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: 230,
              childAspectRatio: 1.3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                for (final app in apps)
                  Card(
                    child: InkWell(
                      key: ValueKey('desktop-library-app-${app.id}'),
                      onTap: () => preview(app),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            _artwork(app),
                            Text(
                              app.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${app.libraryForOS(os)!.actions.length} actions · ${appLibraryOSLabel(os)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Uint8List? desktopLibraryProfileIcon(RemoteProfile profile) {
  try {
    final encoded = profile.sourceIconPngBase64;
    if (encoded == null ||
        encoded.length > 87384 ||
        profile.sourceIconSha256 !=
            registeredAppIconHash(profile.sourceIconId ?? '')) {
      return null;
    }
    final bytes = base64Decode(encoded);
    if (bytes.length > 65536 ||
        sha256.convert(bytes).toString() != profile.sourceIconSha256 ||
        !validApplicationIconPng(bytes)) {
      return null;
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

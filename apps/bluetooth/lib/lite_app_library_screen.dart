import 'package:flutter/material.dart';
import 'app_library/app_library.dart';
import 'icons/builtin_icon_catalog.g.dart';
import 'lite_controller.dart';

class LiteAppLibraryScreen extends StatefulWidget {
  const LiteAppLibraryScreen({super.key, required this.controller});
  final LiteController controller;
  @override
  State<LiteAppLibraryScreen> createState() => _LiteAppLibraryScreenState();
}

class _LiteAppLibraryScreenState extends State<LiteAppLibraryScreen> {
  String? _os;
  String _query = '';
  String? _busy;
  String? _error;
  Future<void> _install(AppLibraryApp app) async {
    final os = _os;
    if (os == null || _busy != null) return;
    setState(() {
      _busy = app.id;
      _error = null;
    });
    try {
      await widget.controller.installAppLibrary(app.id, os);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Installed ${app.name}. Choose its local profile to use these keys.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not install this App library. Existing profiles and launch combinations are unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = AppLibraryCatalog.builtin.apps
        .where(
          (app) =>
              app.bundled &&
              (_os == null || app.libraryForOS(_os!) != null) &&
              '${app.id} ${app.name} ${app.aliases.join(' ')}'
                  .toLowerCase()
                  .contains(_query.trim().toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('App library')),
      body: Column(
        key: const ValueKey('lite-app-library-catalog'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('lite-app-library-os'),
                    initialValue: _os,
                    decoration: const InputDecoration(
                      labelText: 'Controlled computer OS',
                    ),
                    hint: const Text('Choose explicitly'),
                    items: const [
                      DropdownMenuItem(value: 'macos', child: Text('macOS')),
                      DropdownMenuItem(
                        value: 'windows',
                        child: Text('Windows'),
                      ),
                      DropdownMenuItem(value: 'linux', child: Text('Linux')),
                    ],
                    onChanged: _busy != null
                        ? null
                        : (value) => setState(() => _os = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('lite-app-library-search'),
                    decoration: const InputDecoration(labelText: 'Search Apps'),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Offline icons and shortcut libraries install together. Unassigned keys send nothing until configured. Private app-launch combinations are unchanged.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                key: const ValueKey('lite-app-library-error'),
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('lite-app-library-list'),
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index],
                    library = _os == null
                        ? null
                        : apps[index].libraryForOS(_os!);
                final icon = builtinIconById(app.iconId);
                return Card(
                  child: ExpansionTile(
                    key: ValueKey('lite-app-library-${app.id}'),
                    leading: icon == null
                        ? const Icon(Icons.apps)
                        : Image.asset(icon.assetPath, width: 36, height: 36),
                    title: Text(app.name),
                    subtitle: Text(
                      '${app.supportedOS.map(appLibraryOSLabel).join(' / ')} · ${library == null ? 'Choose the computer OS' : '${library.actions.where((a) => a.isConfigured).length}/${library.actions.length} assigned · ${appLibraryContextLabel(library.context)}'}',
                    ),
                    children: [
                      if (library != null) ...[
                        for (final action in library.actions)
                          ListTile(
                            dense: true,
                            title: Text(action.title),
                            subtitle: Text(
                              action.isConfigured
                                  ? formatAppLibraryChord(action.keys, _os!)
                                  : 'Not configured — choose a combination after installation',
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            'Source: ${library.sourceUrls.join('\n')}\nLibrary ${library.id} · version ${library.version}',
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton(
                          key: ValueKey('lite-install-app-${app.id}'),
                          onPressed: library == null || _busy != null
                              ? null
                              : () => _install(app),
                          child: Text(
                            _busy == app.id
                                ? 'Installing…'
                                : 'Install icon + shortcuts (new copy)',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

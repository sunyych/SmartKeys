import 'package:flutter/material.dart';
import 'icons/builtin_icon_catalog.g.dart';
import 'lite_controller.dart';
import 'local_launcher.dart';
import 'local_profiles.dart';

String shortcutDescription(LocalShortcut shortcut) =>
    shortcut.requiresConfiguration
    ? 'Not configured — choose a keyboard combination'
    : shortcut.isConsumer
    ? shortcut.consumerUsage!.replaceAll('_', ' ')
    : [
        ...shortcut.modifiers.map((value) => value.replaceFirst('LEFT_', '')),
        shortcut.keyCode,
      ].join(' + ');

class LiteShortcutEditor extends StatefulWidget {
  const LiteShortcutEditor({
    super.key,
    this.existing,
    this.keyboardOnly = false,
  });
  final LocalShortcut? existing;
  final bool keyboardOnly;
  @override
  State<LiteShortcutEditor> createState() => _LiteShortcutEditorState();
}

class _LiteShortcutEditorState extends State<LiteShortcutEditor> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final keyCode = TextEditingController(
    text: widget.existing?.keyCode ?? '',
  );
  late bool consumer =
      !widget.keyboardOnly && (widget.existing?.isConsumer ?? false);
  late String usage = widget.existing?.consumerUsage ?? 'PLAY_PAUSE';
  late final modifiers = {...?widget.existing?.modifiers};
  final form = GlobalKey<FormState>();
  static const usages = [
    'PLAY_PAUSE',
    'MUTE',
    'VOLUME_UP',
    'VOLUME_DOWN',
    'NEXT_TRACK',
    'PREVIOUS_TRACK',
    'STOP',
  ];
  @override
  void dispose() {
    title.dispose();
    keyCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.keyboardOnly ? 'Keyboard launch combination' : 'Shortcut',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('lite-shortcut-name'),
                controller: title,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              if (!widget.keyboardOnly)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Media control'),
                  value: consumer,
                  onChanged: (value) => setState(() => consumer = value),
                ),
              if (consumer)
                DropdownButtonFormField<String>(
                  initialValue: usages.contains(usage) ? usage : 'PLAY_PAUSE',
                  decoration: const InputDecoration(labelText: 'Media action'),
                  items: [
                    for (final value in usages)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (value) => setState(() => usage = value!),
                )
              else ...[
                TextFormField(
                  key: const ValueKey('lite-shortcut-key'),
                  controller: keyCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Key (A–Z, 0–9, F1–F12, Enter…)',
                  ),
                  validator: (value) =>
                      LocalShortcut.validKey((value ?? '').trim().toUpperCase())
                      ? null
                      : 'Enter a supported keyboard key',
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final value in LocalShortcut.modifierNames)
                      FilterChip(
                        label: Text(value.replaceFirst('LEFT_', '')),
                        selected: modifiers.contains(value),
                        onSelected: (on) => setState(() {
                          on ? modifiers.add(value) : modifiers.remove(value);
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('lite-shortcut-apply'),
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final value = consumer
              ? LocalShortcut.consumer(title: title.text.trim(), usage: usage)
              : LocalShortcut(
                  title: title.text.trim(),
                  keyCode: keyCode.text.trim().toUpperCase(),
                  modifiers: modifiers.toList(),
                );
          Navigator.pop(context, value);
        },
        child: const Text('Apply'),
      ),
    ],
  );
}

class LiteIconField extends StatelessWidget {
  const LiteIconField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('lite-icon-field-${value ?? 'none'}'),
    initialValue: builtinIconById(value ?? '')?.id ?? '',
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Offline icon'),
    items: [
      const DropdownMenuItem(value: '', child: Text('No icon')),
      for (final entry in builtinIconCatalog)
        DropdownMenuItem(
          value: entry.id,
          child: Row(
            children: [
              Image.asset(entry.assetPath, width: 24, height: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
    ],
    onChanged: (id) => onChanged(id == '' ? null : id),
  );
}

class LiteProfileEditor extends StatefulWidget {
  const LiteProfileEditor({super.key, required this.controller, this.profile});
  final LiteController controller;
  final LocalProfile? profile;
  @override
  State<LiteProfileEditor> createState() => _LiteProfileEditorState();
}

class _LiteProfileEditorState extends State<LiteProfileEditor> {
  late final name = TextEditingController(text: widget.profile?.name ?? '');
  late String? iconId = widget.profile?.iconId;
  late final shortcuts = [...?widget.profile?.shortcuts];
  late final id =
      widget.profile?.id ?? 'local_${DateTime.now().microsecondsSinceEpoch}';
  bool saving = false;
  String? error;
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> edit([int? index]) async {
    final value = await showDialog<LocalShortcut>(
      context: context,
      builder: (_) =>
          LiteShortcutEditor(existing: index == null ? null : shortcuts[index]),
    );
    if (value != null && mounted) {
      setState(() {
        index == null ? shortcuts.add(value) : shortcuts[index] = value;
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveProfile(
        widget.profile != null && iconId == widget.profile!.iconId
            ? widget.profile!.copyWith(
                name: name.text.trim(),
                shortcuts: List.of(shortcuts),
              )
            : LocalProfile(
                id: id,
                name: name.text.trim(),
                iconId: iconId,
                shortcuts: List.of(shortcuts),
              ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Could not save this profile. Your saved configuration is unchanged.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.profile == null ? 'New profile' : 'Edit profile'),
      actions: [
        TextButton(
          key: const ValueKey('lite-profile-save'),
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
    body: AbsorbPointer(
      absorbing: saving,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null)
              Text(
                error!,
                key: const ValueKey('lite-editor-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextFormField(
              key: const ValueKey('lite-profile-name'),
              controller: name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Profile name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a profile name'
                  : null,
            ),
            LiteIconField(
              value: iconId,
              onChanged: (value) => setState(() => iconId = value),
            ),
            const SizedBox(height: 16),
            const Text(
              'Shortcuts stay on this phone. Lists longer than 12 keys use additional pages.',
            ),
            for (var index = 0; index < shortcuts.length; index++)
              ListTile(
                key: ValueKey('lite-edit-shortcut-$index'),
                title: Text(shortcuts[index].title),
                subtitle: Text(shortcutDescription(shortcuts[index])),
                onTap: () => edit(index),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Move shortcut up',
                      onPressed: index == 0
                          ? null
                          : () => setState(() {
                              final item = shortcuts.removeAt(index);
                              shortcuts.insert(index - 1, item);
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Delete shortcut',
                      onPressed: () =>
                          setState(() => shortcuts.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('lite-add-shortcut'),
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add shortcut'),
            ),
          ],
        ),
      ),
    ),
  );
}

class LiteLaunchSlotEditor extends StatefulWidget {
  const LiteLaunchSlotEditor({
    super.key,
    required this.controller,
    required this.index,
  });
  final LiteController controller;
  final int index;
  @override
  State<LiteLaunchSlotEditor> createState() => _LiteLaunchSlotEditorState();
}

class _LiteLaunchSlotEditorState extends State<LiteLaunchSlotEditor> {
  late final original = widget.controller.launcherSlots[widget.index];
  late final title = TextEditingController(text: original.title);
  late String? iconId = original.iconId;
  late String? profileId =
      widget.controller.profiles.any(
        (profile) => profile.id == original.profileId,
      )
      ? original.profileId
      : null;
  late LocalShortcut? binding = original.launchShortcut;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> editBinding() async {
    final value = await showDialog<LocalShortcut>(
      context: context,
      builder: (_) => LiteShortcutEditor(existing: binding, keyboardOnly: true),
    );
    if (value != null && mounted) setState(() => binding = value);
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty && binding != null) {
      setState(
        () => error = 'Enter a name before enabling a launch combination.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveLaunchSlot(
        widget.index,
        LocalLaunchSlot(
          title: title.text.trim(),
          iconId: iconId,
          profileId: profileId,
          launchShortcut: binding,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Could not save this slot. Its saved launch binding is unchanged.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Launchpad slot ${widget.index + 1}'),
      actions: [
        TextButton(
          key: const ValueKey('lite-slot-save'),
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
    body: AbsorbPointer(
      absorbing: saving,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Text(
              error!,
              key: const ValueKey('lite-editor-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextField(
            key: const ValueKey('lite-slot-name'),
            controller: title,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          LiteIconField(
            value: iconId,
            onChanged: (value) => setState(() => iconId = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue:
                widget.controller.profiles.any(
                  (profile) => profile.id == profileId,
                )
                ? profileId!
                : '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Show profile after sending',
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Stay on Launchpad'),
              ),
              for (final profile in widget.controller.profiles)
                DropdownMenuItem(value: profile.id, child: Text(profile.name)),
            ],
            onChanged: (value) =>
                setState(() => profileId = value == '' ? null : value),
          ),
          const SizedBox(height: 16),
          const Text(
            'Configure the same keyboard combination on the computer. Bluetooth sending does not confirm that an application opened. Names and icons alone never enable launching.',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              binding == null
                  ? 'Launch not configured'
                  : 'Keyboard launch combination',
            ),
            subtitle: binding == null
                ? null
                : Text(shortcutDescription(binding!)),
          ),
          OutlinedButton(
            key: const ValueKey('lite-slot-set-binding'),
            onPressed: editBinding,
            child: const Text('Set keyboard combination'),
          ),
          if (binding != null)
            TextButton(
              key: const ValueKey('lite-slot-clear-binding'),
              onPressed: () => setState(() => binding = null),
              child: const Text('Remove launch binding'),
            ),
          TextButton(
            key: const ValueKey('lite-slot-clear'),
            onPressed: () => setState(() {
              title.clear();
              iconId = null;
              profileId = null;
              binding = null;
            }),
            child: const Text('Clear slot draft'),
          ),
        ],
      ),
    ),
  );
}

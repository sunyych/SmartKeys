import 'package:flutter/material.dart';

import '../app.dart';
import '../models/config.dart';
import 'icon_picker_screen.dart';
import 'widgets/button_face.dart';

class ButtonEditorScreen extends StatefulWidget {
  const ButtonEditorScreen({super.key, required this.position});

  final int position;

  @override
  State<ButtonEditorScreen> createState() => _ButtonEditorScreenState();
}

class _ButtonEditorScreenState extends State<ButtonEditorScreen> {
  late ButtonConfig draft;
  late final TextEditingController labelController;
  late final TextEditingController subtitleController;
  late final TextEditingController actionController;
  late final TextEditingController modifiersController;
  bool initialized = false;
  bool saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    draft = SmartKeysScope.of(context).activeProfile.buttons[widget.position];
    labelController = TextEditingController(text: draft.label);
    subtitleController = TextEditingController(text: draft.subtitle);
    actionController = TextEditingController(
      text: draft.action.type == ActionType.keyboard
          ? draft.action.keyCode
          : draft.action.value,
    );
    modifiersController = TextEditingController(
      text: draft.action.modifiers.join(', '),
    );
    initialized = true;
  }

  @override
  void dispose() {
    if (initialized) {
      labelController.dispose();
      subtitleController.dispose();
      actionController.dispose();
      modifiersController.dispose();
    }
    super.dispose();
  }

  ButtonConfig _currentDraft() => draft.copyWith(
    label: labelController.text.trim(),
    subtitle: subtitleController.text.trim(),
    action: HidAction(
      type: draft.action.type,
      keyCode: draft.action.type == ActionType.keyboard
          ? actionController.text.trim()
          : null,
      value: draft.action.type == ActionType.keyboard
          ? null
          : actionController.text.trim(),
      modifiers: modifiersController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    ),
  );

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await SmartKeysScope.of(context).updateButton(_currentDraft());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save button: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Button ${widget.position + 1}'),
        actions: [
          TextButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Preview',
            child: Center(
              child: SizedBox(
                width: 180,
                height: 120,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    labelController,
                    subtitleController,
                  ]),
                  builder: (context, _) => ButtonFace(
                    button: _currentDraft(),
                    imageStore: controller.imageStore,
                    shortcutLabel: controller.resolveShortcutLabel(
                      _currentDraft(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _SectionCard(
            title: 'Content',
            child: Column(
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(labelText: 'Shortcut text'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show label'),
                  value: draft.showLabel,
                  onChanged: (value) =>
                      setState(() => draft = draft.copyWith(showLabel: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show shortcut'),
                  value: draft.showShortcut,
                  onChanged: (value) => setState(
                    () => draft = draft.copyWith(showShortcut: value),
                  ),
                ),
                _LabeledSlider(
                  label: 'Text size',
                  value: draft.textSize,
                  min: 10,
                  max: 24,
                  onChanged: (value) =>
                      setState(() => draft = draft.copyWith(textSize: value)),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Visual',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<VisualType>(
                  segments: const [
                    ButtonSegment(value: VisualType.none, label: Text('Text')),
                    ButtonSegment(
                      value: VisualType.builtinIcon,
                      label: Text('Icon'),
                    ),
                    ButtonSegment(
                      value: VisualType.customImage,
                      label: Text('Image'),
                    ),
                  ],
                  selected: {draft.visual.type},
                  onSelectionChanged: (selection) => setState(() {
                    final type = selection.single;
                    draft = draft.copyWith(
                      visual: draft.visual.copyWith(
                        type: type,
                        clearValue: type == VisualType.none,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                if (draft.visual.type == VisualType.builtinIcon) ...[
                  OutlinedButton.icon(
                    onPressed: _selectIcon,
                    icon: const Icon(Icons.grid_view),
                    label: Text(
                      draft.visual.value == null
                          ? 'Select icon'
                          : draft.visual.value!,
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Icon size',
                    value: draft.visual.iconSize,
                    min: 18,
                    max: 64,
                    onChanged: (value) => setState(() {
                      draft = draft.copyWith(
                        visual: draft.visual.copyWith(iconSize: value),
                      );
                    }),
                  ),
                  _ColorChooser(
                    label: 'Icon color',
                    selected: draft.visual.tintColor,
                    onChanged: (value) => setState(() {
                      draft = draft.copyWith(
                        visual: value == null
                            ? draft.visual.copyWith(clearTintColor: true)
                            : draft.visual.copyWith(tintColor: value),
                      );
                    }),
                  ),
                ],
                if (draft.visual.type == VisualType.customImage) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectImage(gallery: true),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectImage(gallery: false),
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Files'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<VisualFit>(
                    initialValue: draft.visual.fit,
                    decoration: const InputDecoration(labelText: 'Image fit'),
                    items: VisualFit.values
                        .map(
                          (fit) => DropdownMenuItem(
                            value: fit,
                            child: Text(fit.name),
                          ),
                        )
                        .toList(),
                    onChanged: (fit) => setState(() {
                      draft = draft.copyWith(
                        visual: draft.visual.copyWith(fit: fit),
                      );
                    }),
                  ),
                  _LabeledSlider(
                    label: 'Image scale',
                    value: draft.visual.imageScale,
                    min: 0.75,
                    max: 2,
                    onChanged: (value) => setState(() {
                      draft = draft.copyWith(
                        visual: draft.visual.copyWith(imageScale: value),
                      );
                    }),
                  ),
                  _LabeledSlider(
                    label: 'Horizontal position',
                    value: draft.visual.alignmentX,
                    min: -1,
                    max: 1,
                    onChanged: (value) => setState(() {
                      draft = draft.copyWith(
                        visual: draft.visual.copyWith(alignmentX: value),
                      );
                    }),
                  ),
                  _LabeledSlider(
                    label: 'Vertical position',
                    value: draft.visual.alignmentY,
                    min: -1,
                    max: 1,
                    onChanged: (value) => setState(() {
                      draft = draft.copyWith(
                        visual: draft.visual.copyWith(alignmentY: value),
                      );
                    }),
                  ),
                ],
                _ColorChooser(
                  label: 'Button background',
                  selected: draft.visual.backgroundColor,
                  onChanged: (value) => setState(() {
                    draft = draft.copyWith(
                      visual: value == null
                          ? draft.visual.copyWith(clearBackgroundColor: true)
                          : draft.visual.copyWith(backgroundColor: value),
                    );
                  }),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Action',
            child: Column(
              children: [
                DropdownButtonFormField<ActionType>(
                  initialValue: draft.action.type,
                  decoration: const InputDecoration(labelText: 'Action type'),
                  items: ActionType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.name),
                        ),
                      )
                      .toList(),
                  onChanged: (type) => setState(() {
                    draft = draft.copyWith(
                      action: draft.action.copyWith(type: type),
                    );
                  }),
                ),
                if (draft.action.type != ActionType.none) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: actionController,
                    decoration: InputDecoration(
                      labelText: draft.action.type == ActionType.keyboard
                          ? 'Keyboard key (for example KEY_C)'
                          : draft.action.type == ActionType.companion
                          ? 'Desktop action JSON'
                          : 'Action value',
                      helperText: draft.action.type == ActionType.companion
                          ? 'Handled by the separate Windows/macOS/Linux Companion app.'
                          : null,
                    ),
                  ),
                ],
                if (draft.action.type == ActionType.companion) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Launch ChatGPT'),
                          onPressed: () => setState(
                            () => actionController.text =
                                '{"kind":"launch","target":"ChatGPT"}',
                          ),
                        ),
                        ActionChip(
                          label: const Text('Voice input'),
                          onPressed: () => setState(
                            () =>
                                actionController.text = '{"kind":"voiceInput"}',
                          ),
                        ),
                        ActionChip(
                          label: const Text('Desktop shortcut'),
                          onPressed: () => setState(
                            () => actionController.text =
                                '{"kind":"shortcut","keys":["CTRL","ALT","T"]}',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'For another app, replace ChatGPT with its app name (macOS) '
                    'or executable name/path (Windows/Linux).',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (draft.action.type == ActionType.keyboard) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: modifiersController,
                    decoration: const InputDecoration(
                      labelText: 'Modifiers (comma separated)',
                      hintText: 'PRIMARY, LEFT_SHIFT',
                      helperText:
                          'PRIMARY sends Command on Apple and Ctrl on Windows/Linux.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          _SectionCard(
            title: 'Feedback',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Haptic feedback'),
                  value: draft.hapticEnabled,
                  onChanged: (value) => setState(
                    () => draft = draft.copyWith(hapticEnabled: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sound feedback'),
                  value: draft.soundEnabled,
                  onChanged: (value) => setState(
                    () => draft = draft.copyWith(soundEnabled: value),
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Management',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    controller.copyButton(_currentDraft());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Button configuration copied'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.hasButtonClipboard ? _paste : null,
                  icon: const Icon(Icons.paste),
                  label: const Text('Paste'),
                ),
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset'),
                ),
                OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectIcon() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => IconPickerScreen(selectedId: draft.visual.value),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      draft = draft.copyWith(
        visual: selected.isEmpty
            ? draft.visual.copyWith(type: VisualType.none, clearValue: true)
            : draft.visual.copyWith(
                type: VisualType.builtinIcon,
                value: selected,
              ),
      );
    });
  }

  Future<void> _selectImage({required bool gallery}) async {
    final controller = SmartKeysScope.of(context);
    try {
      final relativePath = gallery
          ? await controller.imageStore.importFromGallery(
              controller.activeProfile.id,
            )
          : await controller.imageStore.importFromFiles(
              controller.activeProfile.id,
            );
      if (relativePath == null || !mounted) return;
      setState(() {
        draft = draft.copyWith(
          visual: draft.visual.copyWith(
            type: VisualType.customImage,
            value: relativePath,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _paste() async {
    final controller = SmartKeysScope.of(context);
    await controller.pasteButton(widget.position);
    _loadFrom(controller.activeProfile.buttons[widget.position]);
  }

  Future<void> _reset() async {
    final controller = SmartKeysScope.of(context);
    await controller.resetButton(widget.position);
    _loadFrom(controller.activeProfile.buttons[widget.position]);
  }

  void _clear() {
    _loadFrom(
      ButtonConfig.empty(widget.position).copyWith(
        label: '',
        visual: const ButtonVisual(),
        action: const HidAction(),
      ),
    );
  }

  void _loadFrom(ButtonConfig button) {
    setState(() {
      draft = button;
      labelController.text = button.label;
      subtitleController.text = button.subtitle;
      actionController.text = button.action.type == ActionType.keyboard
          ? button.action.keyCode ?? ''
          : button.action.value ?? '';
      modifiersController.text = button.action.modifiers.join(', ');
    });
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ${value.toStringAsFixed(1)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorChooser extends StatelessWidget {
  const _ColorChooser({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  static const colors = <int>[
    0xFFFFFFFF,
    0xFF67E8F9,
    0xFF60A5FA,
    0xFFA78BFA,
    0xFFF472B6,
    0xFFFB7185,
    0xFFFBBF24,
    0xFF4ADE80,
    0xFF1E293B,
  ];

  final String label;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Icon(Icons.block, size: 18),
                selected: selected == null,
                onSelected: (_) => onChanged(null),
              ),
              ...colors.map(
                (value) => ChoiceChip(
                  showCheckmark: false,
                  avatar: CircleAvatar(backgroundColor: Color(value)),
                  label: const SizedBox.shrink(),
                  selected: selected == value,
                  onSelected: (_) => onChanged(value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

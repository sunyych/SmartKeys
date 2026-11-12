import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/computer_setup.dart';

/// First connection and per-computer settings flow for the selected computer.
///
/// Saving one computer never changes the app list or key mappings stored for a
/// different computer. For standalone mode, the test is an emitted key chord
/// followed by explicit confirmation that the chosen app opened.
class ComputerSetupWizard extends StatefulWidget {
  const ComputerSetupWizard({
    super.key,
    required this.controller,
    required this.target,
    this.initialSetup,
    this.onSaved,
    this.onCancel,
  });

  final AppController controller;
  final ComputerTarget target;
  final ComputerSetup? initialSetup;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;

  @override
  State<ComputerSetupWizard> createState() => _ComputerSetupWizardState();
}

class _ComputerSetupWizardState extends State<ComputerSetupWizard> {
  late final Set<String> _applicationIds;
  late final Map<String, _AppBindingControllers> _bindingEditors;
  late final Set<String> _confirmedAppLaunches;
  String? _expandedAppId;
  String? _error;
  String? _lastTestedAppId;
  ComputerOperatingSystem? _operatingSystem;
  ComputerOperatingSystem? _savedOperatingSystem;
  bool _saving = false;
  bool _savingOperatingSystem = false;
  bool _testingLaunch = false;

  List<ComputerApplication> get _wizardApplications =>
      widget.target.mode == ComputerMode.standalone
      ? computerApplicationsForOperatingSystem(_operatingSystem)
      : widget.controller.computerApplicationsOnActiveComputer;

  List<ComputerApplication> get _selectedApplications => _wizardApplications
      .where((app) => _applicationIds.contains(app.id))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final initialSetup = widget.initialSetup;
    _savedOperatingSystem =
        initialSetup?.operatingSystem ??
        widget.controller.activeComputerSetup?.operatingSystem;
    _operatingSystem = _savedOperatingSystem ?? widget.target.operatingSystem;
    _applicationIds = initialSetup == null
        ? <String>{}
        : Set<String>.of(initialSetup.applicationIds);
    _confirmedAppLaunches = initialSetup == null
        ? <String>{}
        : Set<String>.of(initialSetup.applicationIds);
    _bindingEditors = {};
  }

  @override
  void dispose() {
    for (final editors in _bindingEditors.values) {
      editors.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apps = _wizardApplications;
    final selected = _selectedApplications;
    final standalone = widget.target.mode == ComputerMode.standalone;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(standalone ? Icons.bluetooth_connected : Icons.computer),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apps on ${widget.target.name}',
                        key: const ValueKey('computer-wizard-title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        standalone
                            ? 'Choose the apps you use on this computer.'
                            : 'Choose which installed apps appear in the top row.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (widget.onCancel != null)
                  IconButton(
                    key: const ValueKey('computer-wizard-cancel'),
                    tooltip: 'Cancel',
                    onPressed: _saving ? null : widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const ValueKey('computer-wizard-scroll'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              children: [
                if (standalone) ...[
                  Text(
                    'Computer operating system',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<ComputerOperatingSystem>(
                    key: const ValueKey('computer-os-choice'),
                    initialValue: _operatingSystem,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Choose or confirm the computer OS',
                      helperText: _operatingSystem == null
                          ? 'Choose the operating system before continuing.'
                          : _operatingSystem == _savedOperatingSystem
                          ? 'Saved for this computer. Change it if needed.'
                          : 'Suggested from the computer name. Confirm that it is correct.',
                    ),
                    items: [
                      for (final os in ComputerOperatingSystem.values)
                        DropdownMenuItem(
                          key: ValueKey('computer-os-${os.name}'),
                          value: os,
                          child: Text(os.label),
                        ),
                    ],
                    onChanged:
                        _saving || _savingOperatingSystem || _testingLaunch
                        ? null
                        : (operatingSystem) =>
                              _selectOperatingSystem(operatingSystem),
                  ),
                  if (_operatingSystem != null &&
                      _operatingSystem != _savedOperatingSystem) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('computer-confirm-operating-system'),
                      onPressed:
                          _saving || _savingOperatingSystem || _testingLaunch
                          ? null
                          : _confirmOperatingSystem,
                      icon: _savingOperatingSystem
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.computer),
                      label: Text(
                        'Confirm ' +
                            _operatingSystem!.label +
                            ' for this computer',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('电脑系统每台电脑单独保存。选好后点击上方按钮确认；下次连接会自动使用已保存的系统。'),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 16),
                ],
                if (apps.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No apps are available for this computer.'),
                    ),
                  )
                else ...[
                  Text(
                    standalone
                        ? 'Apps on this computer'
                        : 'Apps for Desktop mode',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  for (final app in apps)
                    CheckboxListTile(
                      key: ValueKey('computer-app-select-${app.id}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      value: _applicationIds.contains(app.id),
                      title: Text(app.name),
                      subtitle: Text(_categoryDescription(app.category)),
                      onChanged: _saving || _savingOperatingSystem
                          ? null
                          : (selected) =>
                                _selectApplication(app, selected ?? false),
                    ),
                ],
                if (selected.isNotEmpty &&
                    standalone &&
                    _operatingSystem != null &&
                    widget.controller.config.preferences.beginnerMode) ...[
                  const SizedBox(height: 12),
                  _BeginnerShortcutGuide(operatingSystem: _operatingSystem!),
                ],
                if (selected.isNotEmpty && standalone) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Shortcuts for this computer',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '先在电脑上设置快捷键，再在这里选择相同按键，测试并确认。\nSet each shortcut on the computer, choose the same keys here, then test and confirm.',
                  ),
                  const SizedBox(height: 10),
                  for (final app in selected) _applicationCard(app),
                ],
                if (selected.isNotEmpty && !standalone) ...[
                  const SizedBox(height: 14),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'LumiaKey Desktop supplies the app list and managed shortcuts. Saving your selection puts these apps in the top row.',
                      ),
                    ),
                  ),
                ],
                if (selected.isEmpty && apps.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'General only. You can select apps on this computer later.',
                      key: ValueKey('computer-wizard-general-only'),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('computer-wizard-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('computer-wizard-save'),
                  onPressed:
                      _canSave(selected, standalone) &&
                          !_saving &&
                          !_savingOperatingSystem
                      ? () => _save(selected)
                      : null,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saveLabel(selected, standalone)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _applicationCard(ComputerApplication app) {
    final expanded = _expandedAppId == app.id;
    final shortcuts = computerShortcutsFor(app.category);
    final launch = _bindingEditor(app, 'launch').text.trim();
    final launchConfigured = parseComputerShortcut(launch) != null;
    final launchConfirmed = _confirmedAppLaunches.contains(app.id);
    return Card(
      key: ValueKey('computer-app-settings-${app.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text(app.name),
            subtitle: Text(
              _launchStatus(app, launchConfigured, launchConfirmed),
            ),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() {
              _expandedAppId = expanded ? null : app.id;
            }),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (shortcuts.any((shortcut) => shortcut.id == 'launch'))
                    const _LaunchChordInstructions(),
                  if (shortcuts.any((shortcut) => shortcut.id == 'launch'))
                    const SizedBox(height: 8),
                  for (final shortcut in shortcuts) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: ValueKey(
                                'computer-key-picker-${app.id}-${shortcut.id}',
                              ),
                              onPressed: _saving || _savingOperatingSystem
                                  ? null
                                  : () => _chooseShortcut(app, shortcut),
                              icon: const Icon(Icons.keyboard),
                              label: const Text('Choose keys / 选择按键'),
                            ),
                          ),
                          TextField(
                            key: ValueKey(
                              'computer-key-${app.id}-${shortcut.id}',
                            ),
                            controller: _bindingEditor(app, shortcut.id),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _bindingChanged(app, shortcut),
                            decoration: InputDecoration(
                              labelText: shortcut.id == 'launch'
                                  ? 'Launch app · key combination'
                                  : '${shortcut.label} · key combination',
                              hintText: _shortcutHint(app, shortcut),
                              helperText:
                                  shortcut.requiredForSetup ||
                                      _shortcutHint(app, shortcut) == null
                                  ? null
                                  : 'Default: ${_shortcutHint(app, shortcut)}. Leave blank to use it.',
                              helperMaxLines: 2,
                              suffixIcon: IconButton(
                                tooltip: 'Clear ${shortcut.label}',
                                onPressed: _saving || _savingOperatingSystem
                                    ? null
                                    : () {
                                        _bindingEditor(
                                          app,
                                          shortcut.id,
                                        ).clear();
                                        _bindingChanged(app, shortcut);
                                      },
                                icon: const Icon(Icons.clear),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shortcut.id == 'launch') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: ValueKey('computer-test-launch-${app.id}'),
                        onPressed:
                            launchConfigured &&
                                _operatingSystem != null &&
                                !_testingLaunch &&
                                !_saving
                            ? () => _testLaunch(app)
                            : null,
                        icon: _testingLaunch && _lastTestedAppId == app.id
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: const Text('Test app launch shortcut'),
                      ),
                      if (_lastTestedAppId == app.id && launchConfigured)
                        CheckboxListTile(
                          key: ValueKey('computer-confirm-launch-${app.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: launchConfirmed,
                          title: const Text('I saw this app open'),
                          subtitle: const Text(
                            'Confirm after LumiaKey sends the shortcut.',
                          ),
                          onChanged: _saving
                              ? null
                              : (confirmed) => setState(() {
                                  if (confirmed == true) {
                                    _confirmedAppLaunches.add(app.id);
                                  } else {
                                    _confirmedAppLaunches.remove(app.id);
                                  }
                                }),
                        ),
                    ],
                  ],
                  if (_setupBlocker(app) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _setupBlocker(app)!,
                        key: ValueKey('computer-app-setup-guidance-${app.id}'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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

  TextEditingController _bindingEditor(
    ComputerApplication app,
    String actionId,
  ) => _bindingEditors
      .putIfAbsent(app.id, () {
        final result = <String, TextEditingController>{};
        for (final shortcut in computerShortcutsFor(app.category)) {
          final saved = widget.initialSetup?.bindingFor(app.id, shortcut.id);
          result[shortcut.id] = TextEditingController(text: saved ?? '');
        }
        return _AppBindingControllers(result);
      })
      .forAction(actionId);

  String? _shortcutHint(ComputerApplication app, ComputerShortcut shortcut) {
    final operatingSystem = _operatingSystem;
    if (operatingSystem == null) return null;
    final previewTarget = widget.target.withOperatingSystem(operatingSystem);
    return defaultComputerShortcut(previewTarget, app, shortcut.id);
  }

  void _selectOperatingSystem(ComputerOperatingSystem? operatingSystem) {
    if (operatingSystem == null) return;
    if (operatingSystem != _operatingSystem) {
      setState(() {
        _operatingSystem = operatingSystem;
        _confirmedAppLaunches.clear();
        _lastTestedAppId = null;
        _error = null;
      });
    }
    unawaited(_confirmOperatingSystem());
  }

  Future<void> _confirmOperatingSystem() async {
    final operatingSystem = _operatingSystem;
    if (operatingSystem == null || _savedOperatingSystem == operatingSystem) {
      return;
    }
    setState(() => _savingOperatingSystem = true);
    try {
      await widget.controller.saveComputerOperatingSystem(
        widget.target,
        operatingSystem,
      );
      if (!mounted) return;
      setState(() => _savedOperatingSystem = operatingSystem);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _savingOperatingSystem = false);
    }
  }

  void _selectApplication(ComputerApplication app, bool selected) {
    setState(() {
      if (selected) {
        _applicationIds.add(app.id);
        _bindingEditor(app, 'launch');
        _expandedAppId ??= app.id;
      } else {
        _applicationIds.remove(app.id);
        _confirmedAppLaunches.remove(app.id);
        if (_expandedAppId == app.id) _expandedAppId = null;
      }
      _error = null;
    });
  }

  void _bindingChanged(ComputerApplication app, ComputerShortcut shortcut) {
    if (shortcut.id == 'launch') {
      _confirmedAppLaunches.remove(app.id);
      if (_lastTestedAppId == app.id) _lastTestedAppId = null;
    }
    setState(() => _error = null);
  }

  Future<void> _chooseShortcut(
    ComputerApplication app,
    ComputerShortcut shortcut,
  ) async {
    final chord = await showDialog<String>(
      context: context,
      builder: (context) => _ShortcutChordPicker(
        initialChord: _bindingEditor(app, shortcut.id).text,
        operatingSystem: _operatingSystem,
        title: shortcut.label,
      ),
    );
    if (!mounted || chord == null) return;
    _bindingEditor(app, shortcut.id).text = chord;
    _bindingChanged(app, shortcut);
  }

  String _launchStatus(
    ComputerApplication app,
    bool launchConfigured,
    bool launchConfirmed,
  ) {
    if (_operatingSystem == null || _savedOperatingSystem != _operatingSystem) {
      return 'Step 1 · Confirm this computer’s operating system above.';
    }
    if (!launchConfigured) {
      return 'Step 2 · Choose the same keys you assigned on the computer.';
    }
    if (!launchConfirmed) {
      return 'Step 3 · Test the shortcut and confirm that the app opens.';
    }
    if (_setupBlocker(app) == null) return 'Launch tested. Ready to save.';
    return 'Set the required shortcuts before saving.';
  }

  String? _setupBlocker(ComputerApplication app) {
    if (_operatingSystem == null || _savedOperatingSystem != _operatingSystem) {
      return 'Confirm this computer’s operating system before saving.';
    }
    final shortcuts = computerShortcutsFor(app.category);
    for (final shortcut in shortcuts) {
      final chord = _bindingEditor(app, shortcut.id).text.trim();
      if (shortcut.requiredForSetup && parseComputerShortcut(chord) == null) {
        return 'Choose a valid key combination for ${shortcut.label}.';
      }
      if (chord.isNotEmpty && parseComputerShortcut(chord) == null) {
        return 'The ${shortcut.label.toLowerCase()} combination is not supported.';
      }
    }
    if (app.category == ComputerAppCategory.vibeCoding &&
        _sameChord(
          _bindingEditor(app, 'voiceMode').text,
          _bindingEditor(app, 'voiceInput').text,
        )) {
      return 'Voice mode and voice input need different combinations.';
    }
    final launch = _bindingEditor(app, 'launch').text;
    final duplicate = _selectedApplications.where((other) {
      if (other.id == app.id) return false;
      return _sameChord(launch, _bindingEditor(other, 'launch').text);
    });
    if (duplicate.isNotEmpty) {
      return 'This launch combination is already assigned to ${duplicate.first.name}.';
    }
    if (!_confirmedAppLaunches.contains(app.id)) {
      return 'Test the launch combination and confirm that the app opens.';
    }
    return null;
  }

  static bool _sameChord(String first, String second) {
    final firstAction = parseComputerShortcut(first);
    final secondAction = parseComputerShortcut(second);
    if (firstAction == null || secondAction == null) return false;
    final firstModifiers = firstAction.modifiers.toSet();
    final secondModifiers = secondAction.modifiers.toSet();
    return firstAction.keyCode == secondAction.keyCode &&
        firstModifiers.length == secondModifiers.length &&
        firstModifiers.containsAll(secondModifiers);
  }

  Future<void> _testLaunch(ComputerApplication app) async {
    final chord = _bindingEditor(app, 'launch').text.trim();
    if (_operatingSystem == null || parseComputerShortcut(chord) == null) {
      return;
    }
    setState(() {
      _testingLaunch = true;
      _lastTestedAppId = null;
      _error = null;
    });
    try {
      await widget.controller.testComputerLaunch(widget.target, app.id, chord);
      if (!mounted) return;
      if (!_applicationIds.contains(app.id) ||
          _bindingEditor(app, 'launch').text.trim() != chord) {
        return;
      }
      setState(() {
        _lastTestedAppId = app.id;
        _confirmedAppLaunches.remove(app.id);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _testingLaunch = false);
    }
  }

  bool _canSave(List<ComputerApplication> selected, bool standalone) {
    if (_saving || _testingLaunch) return false;
    if (standalone &&
        (_operatingSystem == null ||
            _savedOperatingSystem != _operatingSystem ||
            _savingOperatingSystem)) {
      return false;
    }
    if (!standalone || selected.isEmpty) return true;
    for (final app in selected) {
      if (!_confirmedAppLaunches.contains(app.id)) return false;
      for (final shortcut in computerShortcutsFor(app.category)) {
        final chord = _bindingEditor(app, shortcut.id).text.trim();
        if (shortcut.requiredForSetup && parseComputerShortcut(chord) == null) {
          return false;
        }
        if (chord.isNotEmpty && parseComputerShortcut(chord) == null) {
          return false;
        }
      }
      final actions = computerShortcutsFor(
        app.category,
      ).map((shortcut) => shortcut.id).toSet();
      if (app.category == ComputerAppCategory.vibeCoding &&
          actions.contains('voiceMode') &&
          actions.contains('voiceInput') &&
          _bindingEditor(app, 'voiceMode').text.trim().toLowerCase() ==
              _bindingEditor(app, 'voiceInput').text.trim().toLowerCase()) {
        return false;
      }
      for (final other in selected) {
        if (other.id != app.id &&
            _sameChord(
              _bindingEditor(app, 'launch').text,
              _bindingEditor(other, 'launch').text,
            )) {
          return false;
        }
      }
    }
    return true;
  }

  String _saveLabel(List<ComputerApplication> selected, bool standalone) {
    if (_saving) return 'Saving…';
    if (selected.isEmpty) return 'Use General only';
    if (!standalone) return 'Use Desktop apps';
    return 'Save settings';
  }

  Future<void> _save(List<ComputerApplication> selected) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bindings = <String, Map<String, String>>{};
      if (widget.target.mode == ComputerMode.standalone) {
        for (final app in selected) {
          final appBindings = <String, String>{};
          for (final shortcut in computerShortcutsFor(app.category)) {
            final chord = _bindingEditor(app, shortcut.id).text.trim();
            if (chord.isNotEmpty) appBindings[shortcut.id] = chord;
          }
          bindings[app.id] = appBindings;
        }
      }
      await widget.controller.saveComputerSetup(
        widget.target,
        ComputerSetup(
          applicationIds: selected.map((app) => app.id).toList(),
          bindings: bindings,
          operatingSystem: _operatingSystem,
          setupComplete: true,
        ),
      );
      if (mounted) widget.onSaved?.call();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _categoryDescription(ComputerAppCategory category) =>
      switch (category) {
        ComputerAppCategory.browser => 'Web browser shortcuts',
        ComputerAppCategory.meetings => 'Meeting controls',
        ComputerAppCategory.vibeCoding => 'Vibe Coding actions',
        ComputerAppCategory.other => 'Application shortcuts',
      };
}

class _BeginnerShortcutGuide extends StatelessWidget {
  const _BeginnerShortcutGuide({required this.operatingSystem});

  final ComputerOperatingSystem operatingSystem;

  @override
  Widget build(BuildContext context) {
    final steps = switch (operatingSystem) {
      ComputerOperatingSystem.windows => const [
        '1. Find the app shortcut in Start or on the Desktop. If missing, search from Start → Open file location, or create a Desktop shortcut first.',
        '2. Right-click → Properties → Shortcut.',
        '3. Set Shortcut key, for example Ctrl+Alt+1, then select OK.',
      ],
      ComputerOperatingSystem.linux => const [
        '1. On GNOME, open Settings → Keyboard → View and Customize Shortcuts.',
        '2. Choose Custom Shortcuts and add a name and app command (for example, firefox).',
        '3. Choose the key combination. Menus vary across Linux desktops.',
      ],
      ComputerOperatingSystem.macos => const [
        '1. Open Shortcuts and create a New Shortcut → Open App.',
        '2. Choose the app, then open Details.',
        '3. Select Add Keyboard Shortcut, for example Cmd+Option+1.',
      ],
    };
    return Card(
      key: const ValueKey('computer-os-beginner-guide'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up shortcuts on ${operatingSystem.label}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(step),
              ),
          ],
        ),
      ),
    );
  }
}

class _LaunchChordInstructions extends StatelessWidget {
  const _LaunchChordInstructions();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Launch app · 启动应用',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text('这里填电脑上的组合键，例如 Ctrl+Alt+1。'),
          SizedBox(height: 4),
          Text(
            'Enter the key combination assigned to open this app, for example Ctrl+Alt+1. Tap “Choose keys” to select it.',
          ),
        ],
      ),
    ),
  );
}

final _shortcutPickerKeys = [
  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
  ...'0123456789'.split(''),
  'Enter',
  'Escape',
  'Backspace',
  'Delete',
  'Tab',
  'Space',
  'Home',
  'End',
  'Insert',
  'Up',
  'Down',
  'Left',
  'Right',
  'PageUp',
  'PageDown',
  'F1',
  'F2',
  'F3',
  'F4',
  'F5',
  'F6',
  'F7',
  'F8',
  'F9',
  'F10',
  'F11',
  'F12',
  'Comma',
  'Period',
  '[',
  ']',
  '-',
  '=',
  '/',
  "'",
];

class _ShortcutChordPicker extends StatefulWidget {
  const _ShortcutChordPicker({
    required this.initialChord,
    required this.operatingSystem,
    required this.title,
  });

  final String initialChord;
  final ComputerOperatingSystem? operatingSystem;
  final String title;

  @override
  State<_ShortcutChordPicker> createState() => _ShortcutChordPickerState();
}

class _ShortcutChordPickerState extends State<_ShortcutChordPicker> {
  late final Set<String> _modifiers;
  late String? _key;

  bool get _isMac => widget.operatingSystem == ComputerOperatingSystem.macos;
  String get _systemModifier => switch (widget.operatingSystem) {
    ComputerOperatingSystem.macos => 'Command',
    ComputerOperatingSystem.linux => 'Meta',
    ComputerOperatingSystem.windows => 'Win',
    null => 'Win',
  };
  String get _systemModifierLabel => switch (widget.operatingSystem) {
    ComputerOperatingSystem.macos => 'Command (⌘)',
    ComputerOperatingSystem.linux => 'Super (Meta)',
    ComputerOperatingSystem.windows => 'Windows (Win)',
    null => 'Windows (Win)',
  };

  @override
  void initState() {
    super.initState();
    final parts = widget.initialChord
        .split('+')
        .map((part) => part.trim())
        .toList();
    _modifiers = {
      for (final part in parts.take(parts.length - 1))
        switch (part.toLowerCase()) {
          'ctrl' || 'control' => 'Ctrl',
          'command' ||
          'cmd' ||
          'meta' ||
          'super' ||
          'win' ||
          'windows' => 'System',
          'alt' || 'option' => _isMac ? 'Option' : 'Alt',
          'shift' => 'Shift',
          _ => '',
        },
    }..remove('');
    final finalKey = parts.isEmpty ? '' : parts.last;
    _key = _shortcutPickerKeys.cast<String?>().firstWhere(
      (candidate) =>
          candidate != null &&
          candidate.toLowerCase() == finalKey.toLowerCase(),
      orElse: () => null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final modifiers = ['Ctrl', 'System', _isMac ? 'Option' : 'Alt', 'Shift'];
    final optionLabel = _isMac ? 'Option (⌥)' : 'Alt';

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose keys · ' + widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('电脑上的按键要和手机选的一致。先选修饰键，再选一个最后按下的键。'),
                    const SizedBox(height: 6),
                    const Text(
                      'Select the modifier keys and one final key. Match the shortcut you set on your computer.',
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Modifier keys · 修饰键',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final modifier in modifiers)
                          FilterChip(
                            key: ValueKey('shortcut-modifier-' + modifier),
                            label: Text(switch (modifier) {
                              'System' => _systemModifierLabel,
                              'Option' || 'Alt' => optionLabel,
                              _ => modifier,
                            }),
                            selected: _modifiers.contains(modifier),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _modifiers.add(modifier);
                              } else {
                                _modifiers.remove(modifier);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('shortcut-final-key'),
                      initialValue: _key,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Final key · 最后一个键',
                      ),
                      items: [
                        for (final key in _shortcutPickerKeys)
                          DropdownMenuItem(value: key, child: Text(key)),
                      ],
                      onChanged: (key) => setState(() => _key = key),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Result · 组合键',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _key == null ? 'Choose a final key.' : _formatChord(),
                      key: const ValueKey('shortcut-picker-preview'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('shortcut-picker-confirm'),
                    onPressed: _key == null
                        ? null
                        : () => Navigator.of(context).pop(_formatChord()),
                    icon: const Icon(Icons.check),
                    label: const Text('Use this shortcut'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatChord() {
    final orderedModifiers = [
      'Ctrl',
      'System',
      _isMac ? 'Option' : 'Alt',
      'Shift',
    ];
    return [
      for (final modifier in orderedModifiers)
        if (_modifiers.contains(modifier))
          modifier == 'System' ? _systemModifier : modifier,
      _key!,
    ].join('+');
  }
}

class _AppBindingControllers {
  _AppBindingControllers(this.actions);

  final Map<String, TextEditingController> actions;

  TextEditingController forAction(String actionId) =>
      actions.putIfAbsent(actionId, () => TextEditingController());

  void dispose() {
    for (final controller in actions.values) {
      controller.dispose();
    }
  }
}

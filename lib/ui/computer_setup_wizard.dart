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
  bool _saving = false;
  bool _testingLaunch = false;

  List<ComputerApplication> get _wizardApplications =>
      widget.target.mode == ComputerMode.standalone
      ? computerApplications
      : widget.controller.computerApplicationsOnActiveComputer;

  List<ComputerApplication> get _selectedApplications => _wizardApplications
      .where((app) => _applicationIds.contains(app.id))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final initialSetup = widget.initialSetup;
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
                      onChanged: _saving
                          ? null
                          : (selected) =>
                                _selectApplication(app, selected ?? false),
                    ),
                ],
                if (selected.isNotEmpty && standalone) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Set the shortcuts on the computer',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Open each app on the computer and add the shortcuts shown here. Switch away from or close the app before testing its launch shortcut. Return to LumiaKey and confirm that it opened or came to the front.',
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
                  onPressed: _canSave(selected, standalone) && !_saving
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
    final instruction = _launchInstruction(app);

    return Card(
      key: ValueKey('computer-app-settings-${app.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text(app.name),
            subtitle: Text(
              launchConfirmed
                  ? 'Launch shortcut tested and confirmed.'
                  : launchConfigured
                  ? 'Set the computer shortcut, then test it below.'
                  : 'Add a valid global launch shortcut.',
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
                  Text(instruction),
                  const SizedBox(height: 8),
                  for (final shortcut in shortcuts)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        key: ValueKey('computer-key-${app.id}-${shortcut.id}'),
                        controller: _bindingEditor(app, shortcut.id),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _bindingChanged(app, shortcut),
                        decoration: InputDecoration(
                          labelText: shortcut.label,
                          hintText: 'Ctrl + Alt + 1',
                          helperText: shortcut.id == 'launch'
                              ? 'A global computer shortcut that launches this app.'
                              : null,
                          suffixIcon: IconButton(
                            tooltip: 'Clear ${shortcut.label}',
                            onPressed: _saving
                                ? null
                                : () {
                                    _bindingEditor(app, shortcut.id).clear();
                                    _bindingChanged(app, shortcut);
                                  },
                            icon: const Icon(Icons.clear),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: ValueKey('computer-test-launch-${app.id}'),
                    onPressed: launchConfigured && !_testingLaunch && !_saving
                        ? () => _testLaunch(app)
                        : null,
                    icon: _testingLaunch && _lastTestedAppId == app.id
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
          final fallback = defaultComputerShortcut(
            widget.target,
            app,
            shortcut.id,
          );
          result[shortcut.id] = TextEditingController(
            text: saved ?? fallback ?? '',
          );
        }
        return _AppBindingControllers(result);
      })
      .forAction(actionId);

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

  Future<void> _testLaunch(ComputerApplication app) async {
    final chord = _bindingEditor(app, 'launch').text.trim();
    if (parseComputerShortcut(chord) == null) return;
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
    if (_saving) return false;
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

  String _launchInstruction(ComputerApplication app) => widget.target.isApple
      ? 'On the Mac, open Shortcuts, create an Open App shortcut for ${app.name}, then choose Add Keyboard Shortcut for that shortcut.'
      : 'On Windows, create or find the ${app.name} shortcut in Start or on the Desktop. Open Properties, set its Shortcut key, and choose OK.';
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

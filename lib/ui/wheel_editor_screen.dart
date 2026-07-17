import 'package:flutter/material.dart';

import '../app.dart';
import '../models/config.dart';

class WheelEditorScreen extends StatefulWidget {
  const WheelEditorScreen({super.key});

  @override
  State<WheelEditorScreen> createState() => _WheelEditorScreenState();
}

class _WheelEditorScreenState extends State<WheelEditorScreen> {
  late final TextEditingController modeController;
  late WheelControlType controlType;
  late _ActionDraft clockwise;
  late _ActionDraft counterClockwise;
  late _ActionDraft center;
  late _ActionDraft up;
  late _ActionDraft down;
  late _ActionDraft left;
  late _ActionDraft right;
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final wheel = SmartKeysScope.of(context).activeProfile.wheel;
    modeController = TextEditingController(text: wheel.modeLabel);
    controlType = wheel.controlType;
    clockwise = _ActionDraft.fromAction(wheel.clockwise);
    counterClockwise = _ActionDraft.fromAction(wheel.counterClockwise);
    center = _ActionDraft.fromAction(wheel.center);
    up = _ActionDraft.fromAction(wheel.up);
    down = _ActionDraft.fromAction(wheel.down);
    left = _ActionDraft.fromAction(wheel.left);
    right = _ActionDraft.fromAction(wheel.right);
    initialized = true;
  }

  @override
  void dispose() {
    if (initialized) {
      modeController.dispose();
      clockwise.dispose();
      counterClockwise.dispose();
      center.dispose();
      up.dispose();
      down.dispose();
      left.dispose();
      right.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation control'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: modeController,
            decoration: const InputDecoration(labelText: 'Control label'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<WheelControlType>(
            initialValue: controlType,
            decoration: const InputDecoration(labelText: 'Control style'),
            items: const [
              DropdownMenuItem(
                value: WheelControlType.jog,
                child: Text('Jog wheel'),
              ),
              DropdownMenuItem(
                value: WheelControlType.mousePad,
                child: Text('Mouse direction pad'),
              ),
            ],
            onChanged: (value) {
              if (value != null) _setControlType(value);
            },
          ),
          const SizedBox(height: 16),
          if (controlType == WheelControlType.jog) ...[
            _ActionCard(
              title: 'Clockwise',
              icon: Icons.rotate_right,
              draft: clockwise,
              onTypeChanged: (value) => setState(() => clockwise.type = value),
            ),
            _ActionCard(
              title: 'Counter-clockwise',
              icon: Icons.rotate_left,
              draft: counterClockwise,
              onTypeChanged: (value) =>
                  setState(() => counterClockwise.type = value),
            ),
            _ActionCard(
              title: 'Center button',
              icon: Icons.radio_button_checked,
              draft: center,
              onTypeChanged: (value) => setState(() => center.type = value),
            ),
          ] else ...[
            _ActionCard(
              title: 'Move up',
              icon: Icons.keyboard_arrow_up,
              draft: up,
              onTypeChanged: (value) => setState(() => up.type = value),
            ),
            _ActionCard(
              title: 'Move down',
              icon: Icons.keyboard_arrow_down,
              draft: down,
              onTypeChanged: (value) => setState(() => down.type = value),
            ),
            _ActionCard(
              title: 'Move left',
              icon: Icons.keyboard_arrow_left,
              draft: left,
              onTypeChanged: (value) => setState(() => left.type = value),
            ),
            _ActionCard(
              title: 'Move right',
              icon: Icons.keyboard_arrow_right,
              draft: right,
              onTypeChanged: (value) => setState(() => right.type = value),
            ),
          ],
        ],
      ),
    );
  }

  void _setControlType(WheelControlType value) {
    setState(() {
      controlType = value;
      if (value == WheelControlType.mousePad) {
        _ensureMouseMove(up, 'UP');
        _ensureMouseMove(down, 'DOWN');
        _ensureMouseMove(left, 'LEFT');
        _ensureMouseMove(right, 'RIGHT');
      }
    });
  }

  void _ensureMouseMove(_ActionDraft draft, String direction) {
    if (draft.type != ActionType.none) return;
    draft.type = ActionType.mouseMove;
    draft.codeController.text = direction;
  }

  Future<void> _save() async {
    await SmartKeysScope.of(context).updateWheel(
      WheelConfig(
        controlType: controlType,
        modeLabel: modeController.text.trim(),
        clockwise: clockwise.toAction(),
        counterClockwise: counterClockwise.toAction(),
        center: center.toAction(),
        up: up.toAction(),
        down: down.toAction(),
        left: left.toAction(),
        right: right.toAction(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.icon,
    required this.draft,
    required this.onTypeChanged,
  });

  final String title;
  final IconData icon;
  final _ActionDraft draft;
  final ValueChanged<ActionType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ActionType>(
              initialValue: draft.type,
              decoration: const InputDecoration(labelText: 'Action type'),
              items: ActionType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onTypeChanged(value);
              },
            ),
            if (draft.type != ActionType.none) ...[
              const SizedBox(height: 12),
              TextField(
                controller: draft.codeController,
                decoration: InputDecoration(
                  labelText: draft.type == ActionType.keyboard
                      ? 'Keyboard key'
                      : 'Action value',
                ),
              ),
            ],
            if (draft.type == ActionType.keyboard) ...[
              const SizedBox(height: 12),
              TextField(
                controller: draft.modifiersController,
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
    );
  }
}

class _ActionDraft {
  _ActionDraft({
    required this.type,
    required this.codeController,
    required this.modifiersController,
  });

  factory _ActionDraft.fromAction(HidAction action) => _ActionDraft(
    type: action.type,
    codeController: TextEditingController(
      text: action.type == ActionType.keyboard ? action.keyCode : action.value,
    ),
    modifiersController: TextEditingController(
      text: action.modifiers.join(', '),
    ),
  );

  ActionType type;
  final TextEditingController codeController;
  final TextEditingController modifiersController;

  HidAction toAction() => HidAction(
    type: type,
    keyCode: type == ActionType.keyboard ? codeController.text.trim() : null,
    value: type == ActionType.keyboard ? null : codeController.text.trim(),
    modifiers: modifiersController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(),
  );

  void dispose() {
    codeController.dispose();
    modifiersController.dispose();
  }
}

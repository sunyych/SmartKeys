import 'package:flutter/material.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import '../services/hid_service.dart';
import 'button_editor_screen.dart';
import 'bluetooth_connection_sheet.dart';
import 'profile_management_screen.dart';
import 'settings_screen.dart';
import 'wheel_editor_screen.dart';
import 'widgets/button_face.dart';
import 'widgets/jog_wheel.dart';
import 'widgets/mouse_touchpad.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool editing = false;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    controller.registerLayoutOrientation(landscape);
    final accent = controller.activeProfile.accentColor == null
        ? Theme.of(context).colorScheme.primary
        : Color(controller.activeProfile.accentColor!);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF10151D),
        ),
      ),
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 140),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          ),
          child: landscape
              ? _LandscapePanel(
                  key: const ValueKey('landscape-layout'),
                  controller: controller,
                  editing: editing,
                  onToggleEditing: () =>
                      setState(() => editing = !editing),
                )
              : _PortraitPanel(
                  key: const ValueKey('portrait-layout'),
                  controller: controller,
                  editing: editing,
                  onToggleEditing: () =>
                      setState(() => editing = !editing),
                ),
        ),
      ),
    );
  }
}

class _PortraitPanel extends StatelessWidget {
  const _PortraitPanel({
    super.key,
    required this.controller,
    required this.editing,
  });

  final AppController controller;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: _ButtonGrid(
              controller: controller,
              editing: editing,
              columns: 3,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          key: const ValueKey('wheel-region'),
          flex: 33,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _WheelPanel(controller: controller, editing: editing),
          ),
        ),
      ],
    );
  }
}

class _LandscapePanel extends StatelessWidget {
  const _LandscapePanel({
    super.key,
    required this.controller,
    required this.editing,
  });

  final AppController controller;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _ButtonGrid(
              controller: controller,
              editing: editing,
              columns: 5,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          key: const ValueKey('wheel-region'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _WheelPanel(controller: controller, editing: editing),
          ),
        ),
      ],
    );
  }
}

class _ButtonGrid extends StatelessWidget {
  const _ButtonGrid({
    required this.controller,
    required this.editing,
    required this.columns,
  });

  final AppController controller;
  final bool editing;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final buttons = [...controller.activeProfile.buttons]
      ..sort((a, b) => a.position.compareTo(b.position));
    final rows = (buttons.length / columns).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalSpacing = 4.0;
        const verticalSpacing = 8.0;
        final width =
            (constraints.maxWidth - horizontalSpacing * (columns - 1)) /
            columns;
        final height =
            (constraints.maxHeight - verticalSpacing * (rows - 1)) / rows;
        return GridView.builder(
          key: ValueKey('button-grid-${columns}x$rows'),
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: horizontalSpacing,
            mainAxisSpacing: verticalSpacing,
            childAspectRatio: width / height,
          ),
          itemCount: buttons.length,
          itemBuilder: (context, index) {
            final button = buttons[index];
            final control = Semantics(
              button: true,
              label: '${button.position + 1}. ${button.label}',
              hint: editing ? 'Long press and drag to swap position' : null,
              child: GestureDetector(
                key: ValueKey('control-button-${button.position}'),
                behavior: HitTestBehavior.opaque,
                onTap: editing
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ButtonEditorScreen(position: button.position),
                        ),
                      )
                    : null,
                onTapDown: editing
                    ? null
                    : (_) => controller.pressButton(button),
                onTapUp: editing
                    ? null
                    : (_) => controller.releaseButton(button),
                onTapCancel: editing
                    ? null
                    : () => controller.releaseButton(button),
                child: ButtonFace(
                  button: button,
                  imageStore: controller.imageStore,
                  shortcutLabel: controller.resolveShortcutLabel(button),
                  pressed: controller.pressedPositions.contains(
                    button.position,
                  ),
                  editing: editing,
                ),
              ),
            );
            if (!editing) return control;
            return DragTarget<int>(
              onWillAcceptWithDetails: (details) =>
                  details.data != button.position,
              onAcceptWithDetails: (details) =>
                  controller.swapButtons(details.data, button.position),
              builder: (context, candidates, rejected) {
                final highlighted = candidates.any(
                  (position) => position != button.position,
                );
                return LongPressDraggable<int>(
                  data: button.position,
                  delay: const Duration(milliseconds: 300),
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      key: const ValueKey('button-drag-feedback'),
                      width: width,
                      height: height,
                      child: Transform.scale(
                        scale: 1.04,
                        child: ButtonFace(
                          button: button,
                          imageStore: controller.imageStore,
                          shortcutLabel: controller.resolveShortcutLabel(
                            button,
                          ),
                          pressed: true,
                          editing: true,
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.24, child: control),
                  child: AnimatedScale(
                    scale: highlighted ? 0.94 : 1,
                    duration: const Duration(milliseconds: 90),
                    child: control,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _WheelPanel extends StatelessWidget {
  const _WheelPanel({required this.controller, required this.editing});

  final AppController controller;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final wheel = controller.activeProfile.wheel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(
              absorbing: editing,
              child: wheel.controlType == WheelControlType.mousePad
                  ? MouseDirectionPad(
                      config: wheel,
                      inputEpoch: controller.inputEpoch,
                      onPress: controller.startMouseMove,
                      onRelease: controller.stopMouseMove,
                    )
                  : JogWheel(
                      config: wheel,
                      inputEpoch: controller.inputEpoch,
                      onStep: controller.sendWheelStep,
                      onCenterPress: controller.pressWheelCenter,
                      onCenterRelease: controller.releaseWheelCenter,
                    ),
            ),
            if (editing)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('edit-jog-wheel'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WheelEditorScreen(),
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: CircleAvatar(
                      radius: 16,
                      child: Icon(Icons.edit, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showProfileSelector(
  BuildContext context,
  AppController controller,
) async {
  final profilesById = {
    for (final profile in controller.config.profiles) profile.id: profile,
  };
  final profiles = controller.config.profileOrder
      .map((id) => profilesById[id])
      .whereType<ProfileConfig>()
      .toList();
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Text(
                  'Profiles',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileManagementScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Manage'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: profiles.map((profile) {
                final selected =
                    profile.id == controller.config.activeProfileId;
                return ListTile(
                  leading: Icon(
                    BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
                        Icons.dashboard,
                  ),
                  title: Text(profile.name),
                  subtitle: profile.targetApplication == null
                      ? null
                      : Text(profile.targetApplication!),
                  trailing: selected ? const Icon(Icons.check_circle) : null,
                  onTap: () => Navigator.pop(sheetContext, profile.id),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await controller.switchProfile(selected);
  }
}

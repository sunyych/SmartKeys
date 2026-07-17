import 'dart:async';

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
import 'widgets/mouse_direction_pad.dart';

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
        body: SafeArea(
          child: Column(
            children: [
              _StatusBar(
                controller: controller,
                editing: editing,
                onEdit: () => setState(() => editing = !editing),
              ),
              Expanded(
                child: AnimatedSwitcher(
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
                        )
                      : _PortraitPanel(
                          key: const ValueKey('portrait-layout'),
                          controller: controller,
                          editing: editing,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.controller,
    required this.editing,
    required this.onEdit,
  });

  final AppController controller;
  final bool editing;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final profile = controller.activeProfile;
    final profileIcon =
        BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
        Icons.dashboard_customize_outlined;
    return Container(
      key: const ValueKey('status-bar'),
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF101720),
        border: Border(bottom: BorderSide(color: Color(0xFF263244))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwipeableProfileSelector(
              controller: controller,
              profileName: profile.name,
              profileIcon: profileIcon,
            ),
          ),
          ValueListenableBuilder<HidConnectionStatus>(
            valueListenable: controller.hid.connectionStatus,
            builder: (context, status, _) => _ConnectionChip(
              status: status,
              onTap: () =>
                  showBluetoothConnectionSheet(context, controller.hid),
            ),
          ),
          const Tooltip(
            message: 'Power status',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                Icons.battery_charging_full,
                size: 19,
                color: Colors.white70,
              ),
            ),
          ),
          IconButton(
            tooltip: editing ? 'Done editing' : 'Edit buttons',
            onPressed: onEdit,
            icon: Icon(editing ? Icons.check : Icons.edit_outlined),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SwipeableProfileSelector extends StatefulWidget {
  const _SwipeableProfileSelector({
    required this.controller,
    required this.profileName,
    required this.profileIcon,
  });

  final AppController controller;
  final String profileName;
  final IconData profileIcon;

  @override
  State<_SwipeableProfileSelector> createState() =>
      _SwipeableProfileSelectorState();
}

class _SwipeableProfileSelectorState extends State<_SwipeableProfileSelector> {
  double dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tap to open Profiles · swipe left or right to switch',
      child: GestureDetector(
        key: const ValueKey('profile-swipe-area'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => dragDistance = 0,
        onHorizontalDragUpdate: (details) {
          dragDistance += details.primaryDelta ?? 0;
        },
        onHorizontalDragCancel: () => dragDistance = 0,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          final direction = dragDistance.abs() >= 32
              ? dragDistance.sign
              : velocity.abs() >= 300
              ? velocity.sign
              : 0;
          dragDistance = 0;
          if (direction == 0) return;
          unawaited(
            widget.controller.switchProfileByOffset(direction < 0 ? 1 : -1),
          );
        },
        child: SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            key: const ValueKey('profile-selector'),
            onPressed: () => _showProfileSelector(context, widget.controller),
            icon: Icon(widget.profileIcon, size: 19),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 120),
                    child: Text(
                      widget.profileName,
                      key: ValueKey(widget.profileName),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.status, required this.onTap});

  final HidConnectionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      HidConnectionStatus.connected => (
        'Connected',
        Icons.bluetooth_connected,
        Colors.greenAccent,
      ),
      HidConnectionStatus.connecting => (
        'Connecting',
        Icons.bluetooth_searching,
        Colors.amberAccent,
      ),
      HidConnectionStatus.registering => (
        'Registering',
        Icons.app_registration,
        Colors.amberAccent,
      ),
      HidConnectionStatus.disconnected => (
        'Disconnected',
        Icons.bluetooth_disabled,
        Colors.redAccent,
      ),
      HidConnectionStatus.permissionRequired => (
        'Permission',
        Icons.security,
        Colors.amberAccent,
      ),
      HidConnectionStatus.bluetoothOff => (
        'Bluetooth off',
        Icons.bluetooth_disabled,
        Colors.redAccent,
      ),
      HidConnectionStatus.unavailable => (
        'Unavailable',
        Icons.error_outline,
        Colors.redAccent,
      ),
    };
    return Tooltip(
      message: '$label · tap to manage Bluetooth',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          key: ValueKey('connection-${status.name}'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              if (MediaQuery.sizeOf(context).width > 520) ...[
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontSize: 12)),
              ],
            ],
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

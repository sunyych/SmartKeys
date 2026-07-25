import 'package:flutter/material.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../app.dart';
import '../controllers/app_controller.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import '../models/control_surface_status.dart';
import '../services/hid_service.dart';
import 'button_editor_screen.dart';
import 'bluetooth_connection_sheet.dart';
import 'profile_management_screen.dart';
import 'settings_screen.dart';
import 'shortcut_community_screen.dart';
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
  _HomeTab selectedTab = _HomeTab.keyboard;
  String? selectedApplicationId;
  bool _followForeground = true;
  String? _handledActivationToken;

  @override
  Widget build(BuildContext context) {
    final controller = SmartKeysScope.of(context);
    _consumeDesktopActivation(controller);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    controller.registerLayoutOrientation(landscape);
    final accent = controller.activeProfile.accentColor == null
        ? Theme.of(context).colorScheme.primary
        : Color(controller.activeProfile.accentColor!);
    final selectedApplication = controller.syncedApplications
        .cast<RemoteApplication?>()
        .firstWhere(
          (application) => application?.id == selectedApplicationId,
          orElse: () => null,
        );
    var effectiveTab =
        selectedTab == _HomeTab.application && selectedApplication == null
        ? _HomeTab.keyboard
        : selectedTab == _HomeTab.apps && !controller.hasAppsSync
        ? _HomeTab.keyboard
        : selectedTab;
    if (_followForeground &&
        effectiveTab == _HomeTab.keyboard &&
        controller.foregroundApplicationLayout != null) {
      effectiveTab = _HomeTab.application;
    }
    final effectiveApplication =
        selectedApplication ?? controller.foregroundApplication;
    final remoteLayout = switch (effectiveTab) {
      _HomeTab.codex => controller.remoteCodexLayout,
      _HomeTab.application => controller.layoutForApplication(
        effectiveApplication!,
      ),
      _HomeTab.keyboard => controller.genericSyncedLayout,
      _HomeTab.apps => null,
    };
    final keyboardSurface = landscape
        ? _LandscapePanel(
            key: const ValueKey('landscape-layout'),
            controller: controller,
            editing: remoteLayout == null && editing,
            remoteLayout: remoteLayout,
            onToggleEditing: () => setState(() => editing = !editing),
          )
        : _PortraitPanel(
            key: const ValueKey('portrait-layout'),
            controller: controller,
            editing: remoteLayout == null && editing,
            remoteLayout: remoteLayout,
            onToggleEditing: () => setState(() => editing = !editing),
          );
    void selectTab(_HomeTab tab) => setState(() {
      selectedTab = tab;
      selectedApplicationId = null;
      editing = false;
      _followForeground = false;
    });
    void selectApplication(RemoteApplication application) => setState(() {
      selectedTab = _HomeTab.application;
      selectedApplicationId = application.id;
      editing = false;
      _followForeground = false;
    });
    final content = switch (effectiveTab) {
      _HomeTab.keyboard || _HomeTab.application => keyboardSurface,
      _HomeTab.apps => _SyncedAppsPage(
        controller: controller,
        onOpenApplication: (application) {
          selectApplication(application);
          controller.launchRemoteApplication(application);
        },
      ),
      _HomeTab.codex => keyboardSurface,
    };

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF10151D),
        ),
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 140, 6),
                  child: _HomeTabBar(
                    controller: controller,
                    selectedTab: effectiveTab,
                    selectedApplicationId: effectiveApplication?.id,
                    onSelectTab: selectTab,
                    onSelectApplication: selectApplication,
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            ),
            Positioned(
              top: 7,
              right: 10,
              child: _CompactControlMenu(
                controller: controller,
                editing: editing,
                onToggleEditing: () => setState(() => editing = !editing),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _consumeDesktopActivation(AppController controller) {
    final manifest = controller.desktopManifest;
    final host = controller.companion.activeHost.value;
    final appId = manifest?.activatedApplicationId;
    final sequence = manifest?.applicationActivationSequence ?? 0;
    if (!controller.isDesktopSynced ||
        host == null ||
        appId == null ||
        sequence <= 0) {
      return;
    }
    final token = '${host.token}:$sequence';
    if (_handledActivationToken == token) return;
    final app = controller.syncedApplications
        .cast<RemoteApplication?>()
        .firstWhere(
          (candidate) =>
              candidate?.id == appId && candidate?.foreground == true,
          orElse: () => null,
        );
    if (app == null ||
        controller.layoutForApplication(app)?.buttons.isEmpty != false) {
      return;
    }
    _handledActivationToken = token;
    selectedTab = app.id == 'codex' ? _HomeTab.codex : _HomeTab.application;
    selectedApplicationId = app.id;
    editing = false;
    _followForeground = false;
  }
}

enum _HomeTab { keyboard, application, apps, codex }

extension on _HomeTab {
  String get label => switch (this) {
    _HomeTab.keyboard => 'Keyboard',
    _HomeTab.application => 'Application',
    _HomeTab.apps => 'Apps',
    _HomeTab.codex => 'Codex',
  };

  IconData get icon => switch (this) {
    _HomeTab.keyboard => Icons.keyboard_alt_outlined,
    _HomeTab.application => Icons.layers_outlined,
    _HomeTab.apps => Icons.apps,
    _HomeTab.codex => Icons.auto_awesome,
  };
}

class _PortraitPanel extends StatelessWidget {
  const _PortraitPanel({
    super.key,
    required this.controller,
    required this.editing,
    required this.remoteLayout,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final RemoteShortcutLayout? remoteLayout;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: remoteLayout == null
                ? _ButtonGrid(
                    controller: controller,
                    editing: editing,
                    columns: 3,
                  )
                : _RemoteButtonGrid(
                    controller: controller,
                    layout: remoteLayout!,
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
            child: _WheelPanel(
              controller: controller,
              editing: editing,
              onToggleEditing: onToggleEditing,
            ),
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
    required this.remoteLayout,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final RemoteShortcutLayout? remoteLayout;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          key: const ValueKey('key-region'),
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: remoteLayout == null
                ? _ButtonGrid(
                    controller: controller,
                    editing: editing,
                    columns: 5,
                  )
                : _RemoteButtonGrid(
                    controller: controller,
                    layout: remoteLayout!,
                    columns: 5,
                  ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          key: const ValueKey('wheel-region'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _WheelPanel(
              controller: controller,
              editing: editing,
              onToggleEditing: onToggleEditing,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeTabBar extends StatelessWidget {
  const _HomeTabBar({
    required this.controller,
    required this.selectedTab,
    required this.selectedApplicationId,
    required this.onSelectTab,
    required this.onSelectApplication,
  });

  final AppController controller;
  final _HomeTab selectedTab;
  final String? selectedApplicationId;
  final ValueChanged<_HomeTab> onSelectTab;
  final ValueChanged<RemoteApplication> onSelectApplication;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      ...controller.visibleHomeProfiles.map(
        (profile) => _HomeTabChip(
          key: ValueKey('profile-quick-${profile.id}'),
          label: profile.name,
          icon: Icon(
            BuiltinIconCatalog.find(profile.profileIcon.value)?.icon ??
                Icons.dashboard_outlined,
          ),
          selected:
              selectedTab == _HomeTab.keyboard &&
              profile.id == controller.activeProfile.id,
          onTap: () {
            onSelectTab(_HomeTab.keyboard);
            controller.switchProfile(profile.id);
          },
        ),
      ),
      ...controller.runningApplications
          .where((application) => application.id != 'codex')
          .map(
            (application) => _HomeTabChip(
              key: ValueKey('workspace-app-${application.id}'),
              label: application.name,
              icon: _RemoteApplicationIcon(application: application),
              selected:
                  selectedTab == _HomeTab.application &&
                  selectedApplicationId == application.id,
              onTap: () => onSelectApplication(application),
            ),
          ),
      if (controller.hasAppsSync)
        _HomeTabChip(
          key: const ValueKey('home-tab-apps'),
          label: _HomeTab.apps.label,
          icon: Icon(_HomeTab.apps.icon),
          selected: selectedTab == _HomeTab.apps,
          onTap: () => onSelectTab(_HomeTab.apps),
        ),
      if (controller.hasCodexWorkspace)
        _HomeTabChip(
          key: const ValueKey('home-tab-codex'),
          label: _HomeTab.codex.label,
          icon: const _BrandedAppIcon(
            applicationId: 'codex',
            fallback: Icons.auto_awesome,
          ),
          selected: selectedTab == _HomeTab.codex,
          onTap: () => onSelectTab(_HomeTab.codex),
        ),
    ];
    return SizedBox(
      key: const ValueKey('profile-quick-switch-bar'),
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => items[index],
      ),
    );
  }
}

class _HomeTabChip extends StatelessWidget {
  const _HomeTabChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : const Color(0xFF151C26),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white12,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 16,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Colors.white60,
                  ),
                  child: SizedBox.square(dimension: 16, child: icon),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteButtonGrid extends StatelessWidget {
  const _RemoteButtonGrid({
    required this.controller,
    required this.layout,
    required this.columns,
  });

  final AppController controller;
  final RemoteShortcutLayout layout;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final buttons = layout.buttons.take(controlButtonCount).toList();
    final rows = (controlButtonCount / columns).ceil();
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
          key: ValueKey('remote-layout-${layout.id}'),
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: controlButtonCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: horizontalSpacing,
            mainAxisSpacing: verticalSpacing,
            childAspectRatio: width / height,
          ),
          itemBuilder: (context, index) {
            if (index >= buttons.length) {
              return Material(
                color: const Color(0xFF10151D),
                borderRadius: BorderRadius.circular(14),
              );
            }
            final button = buttons[index];
            return Material(
              color: const Color(0xFF151C26),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('remote-button-${button.id}'),
                onTap: button.enabled
                    ? () => controller.executeRemoteButton(button)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(remoteIcon(button.icon), size: 25),
                      const SizedBox(height: 5),
                      Text(
                        button.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (button.targetType ==
                          RemoteTargetType.keyboardShortcut)
                        Text(
                          formatShortcut(button.shortcut),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SyncedAppsPage extends StatelessWidget {
  const _SyncedAppsPage({
    required this.controller,
    required this.onOpenApplication,
  });

  final AppController controller;
  final ValueChanged<RemoteApplication> onOpenApplication;

  @override
  Widget build(BuildContext context) {
    final apps = controller.syncedApplications;
    if (apps.isEmpty) {
      return const _DesktopRequired(
        message: 'Enable Apps Sync in LumiaKeys Desktop to show applications.',
      );
    }
    final columns = MediaQuery.orientationOf(context) == Orientation.landscape
        ? 5
        : 3;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gridWidth = landscape
              ? constraints.maxWidth * 2 / 3
              : constraints.maxWidth;
          final gridHeight = landscape
              ? constraints.maxHeight
              : constraints.maxHeight * 62 / 95;
          final rows = (controlButtonCount / columns).ceil();
          const horizontalSpacing = 4.0;
          const verticalSpacing = 8.0;
          const horizontalPadding = 10.0;
          const verticalPadding = 10.0;
          final width =
              (gridWidth -
                  horizontalPadding * 2 -
                  horizontalSpacing * (columns - 1)) /
              columns;
          final height =
              (gridHeight -
                  verticalPadding * 2 -
                  verticalSpacing * (rows - 1)) /
              rows;
          return Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: GridView.builder(
                key: const ValueKey('apps-grid'),
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                itemCount: apps.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: horizontalSpacing,
                  mainAxisSpacing: verticalSpacing,
                  childAspectRatio: width / height,
                ),
                itemBuilder: (context, index) {
                  final app = apps[index];
                  return Material(
                    color: const Color(0xFF151C26),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('remote-app-${app.id}'),
                      onTap: () => onOpenApplication(app),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox.square(
                              dimension: 34,
                              child: _RemoteApplicationIcon(application: app),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              app.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              app.running ? 'Running' : 'Open',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RemoteApplicationIcon extends StatelessWidget {
  const _RemoteApplicationIcon({required this.application});

  final RemoteApplication application;

  @override
  Widget build(BuildContext context) => _BrandedAppIcon(
    applicationId: application.icon.isEmpty ? '' : application.id,
    fallback: remoteIcon(application.icon),
  );
}

class _BrandedAppIcon extends StatelessWidget {
  const _BrandedAppIcon({required this.applicationId, required this.fallback});

  final String applicationId;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final asset = _appIconAssets[applicationId];
    return asset == null
        ? Icon(fallback)
        : Image.asset(asset, fit: BoxFit.contain);
  }
}

const _appIconAssets = <String, String>{
  'codex': 'assets/app_icons/openai.png',
  'chrome': 'assets/app_icons/chrome.png',
  'vscode': 'assets/app_icons/vscode.png',
  'photoshop': 'assets/app_icons/photoshop.png',
  'illustrator': 'assets/app_icons/illustrator.png',
  'premiere': 'assets/app_icons/premiere.png',
  'solidworks': 'assets/app_icons/solidworks.png',
};

class _DesktopRequired extends StatelessWidget {
  const _DesktopRequired({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.desktop_access_disabled, size: 54),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

IconData remoteIcon(String id) => switch (id) {
  'copy' => Icons.copy,
  'paste' => Icons.paste,
  'undo' => Icons.undo,
  'redo' => Icons.redo,
  'cut' => Icons.content_cut,
  'play' => Icons.play_arrow,
  'pause' => Icons.pause,
  'skip_next' => Icons.skip_next,
  'skip_previous' => Icons.skip_previous,
  'save' => Icons.save,
  'search' => Icons.search,
  'find_in_page' => Icons.find_in_page_outlined,
  'terminal' => Icons.terminal,
  'code' => Icons.code,
  'bug' => Icons.bug_report,
  'comment' => Icons.comment,
  'format' => Icons.format_align_left,
  'folder_open' => Icons.folder_open,
  'source_control' => Icons.account_tree,
  'image' => Icons.image,
  'draw' => Icons.draw,
  'view_in_ar' => Icons.view_in_ar,
  'movie' => Icons.movie,
  'language' => Icons.language,
  'check' => Icons.check,
  'close' => Icons.close,
  'arrow_next' => Icons.arrow_forward,
  'arrow_back' => Icons.arrow_back,
  'auto_awesome' => Icons.auto_awesome,
  'difference' => Icons.difference,
  'commit' => Icons.commit,
  'upload' => Icons.upload,
  'download' => Icons.download,
  'help' => Icons.help_outline,
  'build' => Icons.build,
  'refresh' => Icons.refresh,
  'export' => Icons.ios_share,
  'transform' => Icons.transform,
  'group' => Icons.group_work,
  'restore' => Icons.restore,
  'link' => Icons.link,
  'bookmark' => Icons.bookmark_outline,
  'password' => Icons.password,
  'volume_off' => Icons.volume_off,
  'volume_up' => Icons.volume_up,
  'volume_down' => Icons.volume_down,
  'music' => Icons.music_note,
  'map' => Icons.map_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'journal' => Icons.edit_note,
  'note' => Icons.note_alt_outlined,
  'home' => Icons.home_outlined,
  'zoom_in' => Icons.zoom_in,
  'zoom_out' => Icons.zoom_out,
  'select_all' => Icons.select_all,
  'find_replace' => Icons.find_replace,
  'print' => Icons.print_outlined,
  'create_new_folder' => Icons.create_new_folder_outlined,
  'info' => Icons.info_outline,
  'delete' => Icons.delete_outline,
  'grid_view' => Icons.grid_view,
  'view_list' => Icons.view_list,
  'view_column' => Icons.view_column,
  'visibility' => Icons.visibility_outlined,
  'add' => Icons.add,
  'mic' => Icons.mic,
  'send' => Icons.send,
  'menu' => Icons.manage_search_outlined,
  'menu_open' => Icons.menu_open,
  'folder_back' => Icons.drive_folder_upload_outlined,
  'folder_next' => Icons.next_plan_outlined,
  'arrow_up' => Icons.keyboard_arrow_up,
  'arrow_down' => Icons.keyboard_arrow_down,
  'stop' => Icons.stop_circle_outlined,
  'science' => Icons.science_outlined,
  _ => Icons.keyboard_command_key,
};

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
                  pressed:
                      controller.pressedPositions.contains(button.position) ||
                      (button.action.type == ActionType.companion &&
                          button.action.value?.contains('"kind":"dark"') ==
                              true &&
                          controller.isDarkModeActive),
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
  const _WheelPanel({
    required this.controller,
    required this.editing,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    final wheel = controller.activeProfile.wheel;
    final isTouchpad = wheel.controlType == WheelControlType.mousePad;
    final panel = Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: editing,
          child: isTouchpad
              ? MouseTouchpad(
                  config: wheel,
                  inputEpoch: controller.inputEpoch,
                  onMove: (delta) =>
                      controller.sendTouchpadMove(delta.dx, delta.dy),
                  onScroll: controller.sendTouchpadScroll,
                  onPrimaryTap: () =>
                      _sendMouseClick(context, secondary: false),
                  onSecondaryTap: () =>
                      _sendMouseClick(context, secondary: true),
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
              key: const ValueKey('edit-navigation-control'),
              borderRadius: BorderRadius.circular(isTouchpad ? 28 : 999),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WheelEditorScreen(),
                ),
              ),
              child: const Align(
                alignment: Alignment.topLeft,
                child: CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.edit, size: 16),
                ),
              ),
            ),
          ),
      ],
    );
    if (isTouchpad) return panel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
        child: panel,
      ),
    );
  }

  void _sendMouseClick(BuildContext context, {required bool secondary}) {
    if (controller.hid.connectionStatus.value !=
        HidConnectionStatus.connected) {
      showBluetoothConnectionSheet(context, controller.hid);
      return;
    }
    controller.sendMouseClick(secondary: secondary);
  }
}

enum _ControlMenuAction {
  profiles,
  bluetooth,
  importExport,
  toggleEditing,
  settings,
}

class _CompactControlMenu extends StatelessWidget {
  const _CompactControlMenu({
    required this.controller,
    required this.editing,
    required this.onToggleEditing,
  });

  final AppController controller;
  final bool editing;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HidConnectionStatus>(
      valueListenable: controller.hid.connectionStatus,
      builder: (context, status, _) => ValueListenableBuilder<bool?>(
        valueListenable: controller.powerBrightnessService.isPluggedIn,
        builder: (context, pluggedIn, _) {
          final display = _statusDisplay(
            controller.controlSurfaceStatus,
            status,
          );
          return SizedBox(
            width: 124,
            height: 40,
            child: PopupMenuButton<_ControlMenuAction>(
              key: const ValueKey('control-menu'),
              tooltip: display.tooltip,
              position: PopupMenuPosition.under,
              padding: EdgeInsets.zero,
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ControlMenuAction.profiles,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: Text('Profiles · ${controller.activeProfile.name}'),
                  ),
                ),
                PopupMenuItem(
                  value: _ControlMenuAction.bluetooth,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_connectionIcon(status)),
                    title: Text('Bluetooth · ${_connectionLabel(status)}'),
                  ),
                ),
                PopupMenuItem(
                  value: _ControlMenuAction.toggleEditing,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(editing ? Icons.check : Icons.edit_outlined),
                    title: Text(editing ? 'Done editing' : 'Edit buttons'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ControlMenuAction.importExport,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.import_export),
                    title: Text('Import / export JSON'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ControlMenuAction.settings,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                  ),
                ),
              ],
              child: Tooltip(
                message: display.tooltip,
                child: Container(
                  key: ValueKey('status-mode-${display.key}'),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xD9101720),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: display.color.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        editing ? Icons.check : display.icon,
                        size: 17,
                        color: display.color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          editing ? 'Editing' : display.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: switch (pluggedIn) {
                          true => 'External power connected',
                          false => 'Running on battery',
                          null => 'Power status unavailable',
                        },
                        child: Icon(
                          pluggedIn == true
                              ? Icons.bolt
                              : pluggedIn == false
                              ? Icons.battery_full
                              : Icons.battery_unknown,
                          key: ValueKey('power-indicator-$pluggedIn'),
                          size: 12,
                          color: pluggedIn == true
                              ? const Color(0xFF7BD4E4)
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static _CompactStatusDisplay _statusDisplay(
    ControlSurfaceStatus surface,
    HidConnectionStatus hidStatus,
  ) {
    if (surface.desktopSynced &&
        surface.foregroundStatus == ForegroundWorkspaceStatus.ready) {
      final name = surface.foregroundApplicationName ?? 'App';
      return _CompactStatusDisplay(
        key: 'app',
        label: name,
        tooltip: 'Foreground app · $name',
        icon: Icons.center_focus_strong,
        color: Colors.lightGreenAccent,
      );
    }
    if (surface.desktopDiscovered) {
      return _CompactStatusDisplay(
        key: 'desktop',
        label: 'Desktop',
        tooltip: surface.desktopSynced
            ? 'LumiaKeys Desktop connected'
            : 'LumiaKeys Desktop syncing',
        icon: Icons.desktop_windows_outlined,
        color: surface.desktopSynced
            ? Colors.lightGreenAccent
            : Colors.amberAccent,
      );
    }
    return _CompactStatusDisplay(
      key: 'hid',
      label: 'HID',
      tooltip: 'Bluetooth HID · ${_connectionLabel(hidStatus)}',
      icon: _connectionIcon(hidStatus),
      color: _connectionColor(hidStatus),
    );
  }

  void _handleAction(BuildContext context, _ControlMenuAction action) {
    switch (action) {
      case _ControlMenuAction.profiles:
        _showProfileSelector(context, controller);
      case _ControlMenuAction.bluetooth:
        showBluetoothConnectionSheet(context, controller.hid);
      case _ControlMenuAction.toggleEditing:
        onToggleEditing();
      case _ControlMenuAction.importExport:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ShortcutCommunityScreen(),
          ),
        );
      case _ControlMenuAction.settings:
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    }
  }

  static String _connectionLabel(HidConnectionStatus status) =>
      switch (status) {
        HidConnectionStatus.connected => 'Connected',
        HidConnectionStatus.connecting => 'Connecting',
        HidConnectionStatus.registering => 'Registering',
        HidConnectionStatus.disconnected => 'Disconnected',
        HidConnectionStatus.permissionRequired => 'Permission required',
        HidConnectionStatus.bluetoothOff => 'Off',
        HidConnectionStatus.unavailable => 'Unavailable',
      };

  static IconData _connectionIcon(HidConnectionStatus status) =>
      switch (status) {
        HidConnectionStatus.connected => Icons.bluetooth_connected,
        HidConnectionStatus.connecting => Icons.bluetooth_searching,
        HidConnectionStatus.registering => Icons.app_registration,
        HidConnectionStatus.disconnected => Icons.bluetooth_disabled,
        HidConnectionStatus.permissionRequired => Icons.security,
        HidConnectionStatus.bluetoothOff => Icons.bluetooth_disabled,
        HidConnectionStatus.unavailable => Icons.error_outline,
      };

  static Color _connectionColor(HidConnectionStatus status) => switch (status) {
    HidConnectionStatus.connected => Colors.greenAccent,
    HidConnectionStatus.connecting ||
    HidConnectionStatus.registering ||
    HidConnectionStatus.permissionRequired => Colors.amberAccent,
    HidConnectionStatus.disconnected ||
    HidConnectionStatus.bluetoothOff ||
    HidConnectionStatus.unavailable => Colors.redAccent,
  };
}

class _CompactStatusDisplay {
  const _CompactStatusDisplay({
    required this.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;
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

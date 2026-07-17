import 'package:flutter/material.dart';

class BuiltinIconDefinition {
  const BuiltinIconDefinition({
    required this.id,
    required this.label,
    required this.category,
    required this.icon,
  });

  final String id;
  final String label;
  final String category;
  final IconData icon;
}

abstract final class BuiltinIconCatalog {
  static const common = 'Common Editing';
  static const navigation = 'Navigation';
  static const media = 'Media';
  static const design = 'Design and Image Tools';
  static const cad = 'CAD and 3D Tools';
  static const device = 'Device and Profile';

  static const entries = <BuiltinIconDefinition>[
    BuiltinIconDefinition(
      id: 'edit.copy',
      label: 'Copy',
      category: common,
      icon: Icons.content_copy,
    ),
    BuiltinIconDefinition(
      id: 'edit.paste',
      label: 'Paste',
      category: common,
      icon: Icons.content_paste,
    ),
    BuiltinIconDefinition(
      id: 'edit.cut',
      label: 'Cut',
      category: common,
      icon: Icons.content_cut,
    ),
    BuiltinIconDefinition(
      id: 'edit.undo',
      label: 'Undo',
      category: common,
      icon: Icons.undo,
    ),
    BuiltinIconDefinition(
      id: 'edit.redo',
      label: 'Redo',
      category: common,
      icon: Icons.redo,
    ),
    BuiltinIconDefinition(
      id: 'file.save',
      label: 'Save',
      category: common,
      icon: Icons.save,
    ),
    BuiltinIconDefinition(
      id: 'file.saveAs',
      label: 'Save As',
      category: common,
      icon: Icons.save_as,
    ),
    BuiltinIconDefinition(
      id: 'edit.delete',
      label: 'Delete',
      category: common,
      icon: Icons.delete_outline,
    ),
    BuiltinIconDefinition(
      id: 'edit.selectAll',
      label: 'Select All',
      category: common,
      icon: Icons.select_all,
    ),
    BuiltinIconDefinition(
      id: 'edit.search',
      label: 'Search',
      category: common,
      icon: Icons.search,
    ),
    BuiltinIconDefinition(
      id: 'file.open',
      label: 'Open',
      category: common,
      icon: Icons.folder_open,
    ),
    BuiltinIconDefinition(
      id: 'file.new',
      label: 'New File',
      category: common,
      icon: Icons.note_add_outlined,
    ),
    BuiltinIconDefinition(
      id: 'file.close',
      label: 'Close',
      category: common,
      icon: Icons.close,
    ),
    BuiltinIconDefinition(
      id: 'file.favorite',
      label: 'Favorite',
      category: common,
      icon: Icons.star_border,
    ),
    BuiltinIconDefinition(
      id: 'key.enter',
      label: 'Enter',
      category: common,
      icon: Icons.keyboard_return,
    ),
    BuiltinIconDefinition(
      id: 'key.escape',
      label: 'Escape',
      category: common,
      icon: Icons.cancel_outlined,
    ),
    BuiltinIconDefinition(
      id: 'nav.left',
      label: 'Arrow Left',
      category: navigation,
      icon: Icons.arrow_back,
    ),
    BuiltinIconDefinition(
      id: 'nav.right',
      label: 'Arrow Right',
      category: navigation,
      icon: Icons.arrow_forward,
    ),
    BuiltinIconDefinition(
      id: 'nav.up',
      label: 'Arrow Up',
      category: navigation,
      icon: Icons.arrow_upward,
    ),
    BuiltinIconDefinition(
      id: 'nav.down',
      label: 'Arrow Down',
      category: navigation,
      icon: Icons.arrow_downward,
    ),
    BuiltinIconDefinition(
      id: 'nav.home',
      label: 'Home',
      category: navigation,
      icon: Icons.home_outlined,
    ),
    BuiltinIconDefinition(
      id: 'nav.end',
      label: 'End',
      category: navigation,
      icon: Icons.vertical_align_bottom,
    ),
    BuiltinIconDefinition(
      id: 'nav.previous',
      label: 'Previous',
      category: navigation,
      icon: Icons.skip_previous,
    ),
    BuiltinIconDefinition(
      id: 'nav.next',
      label: 'Next',
      category: navigation,
      icon: Icons.skip_next,
    ),
    BuiltinIconDefinition(
      id: 'nav.back',
      label: 'Back',
      category: navigation,
      icon: Icons.chevron_left,
    ),
    BuiltinIconDefinition(
      id: 'nav.forward',
      label: 'Forward',
      category: navigation,
      icon: Icons.chevron_right,
    ),
    BuiltinIconDefinition(
      id: 'view.zoomIn',
      label: 'Zoom In',
      category: navigation,
      icon: Icons.zoom_in,
    ),
    BuiltinIconDefinition(
      id: 'view.zoomOut',
      label: 'Zoom Out',
      category: navigation,
      icon: Icons.zoom_out,
    ),
    BuiltinIconDefinition(
      id: 'view.fit',
      label: 'Fit to Screen',
      category: navigation,
      icon: Icons.fit_screen,
    ),
    BuiltinIconDefinition(
      id: 'media.play',
      label: 'Play',
      category: media,
      icon: Icons.play_arrow,
    ),
    BuiltinIconDefinition(
      id: 'media.pause',
      label: 'Pause',
      category: media,
      icon: Icons.pause,
    ),
    BuiltinIconDefinition(
      id: 'media.playPause',
      label: 'Play/Pause',
      category: media,
      icon: Icons.play_circle_outline,
    ),
    BuiltinIconDefinition(
      id: 'media.stop',
      label: 'Stop',
      category: media,
      icon: Icons.stop,
    ),
    BuiltinIconDefinition(
      id: 'media.previousTrack',
      label: 'Previous Track',
      category: media,
      icon: Icons.skip_previous,
    ),
    BuiltinIconDefinition(
      id: 'media.nextTrack',
      label: 'Next Track',
      category: media,
      icon: Icons.skip_next,
    ),
    BuiltinIconDefinition(
      id: 'media.volumeUp',
      label: 'Volume Up',
      category: media,
      icon: Icons.volume_up,
    ),
    BuiltinIconDefinition(
      id: 'media.volumeDown',
      label: 'Volume Down',
      category: media,
      icon: Icons.volume_down,
    ),
    BuiltinIconDefinition(
      id: 'media.mute',
      label: 'Mute',
      category: media,
      icon: Icons.volume_off,
    ),
    BuiltinIconDefinition(
      id: 'media.record',
      label: 'Record',
      category: media,
      icon: Icons.fiber_manual_record,
    ),
    BuiltinIconDefinition(
      id: 'design.pointer',
      label: 'Pointer',
      category: design,
      icon: Icons.mouse_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.move',
      label: 'Move',
      category: design,
      icon: Icons.open_with,
    ),
    BuiltinIconDefinition(
      id: 'design.pen',
      label: 'Pen',
      category: design,
      icon: Icons.draw_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.pencil',
      label: 'Pencil',
      category: design,
      icon: Icons.edit_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.brush',
      label: 'Brush',
      category: design,
      icon: Icons.brush,
    ),
    BuiltinIconDefinition(
      id: 'design.eraser',
      label: 'Eraser',
      category: design,
      icon: Icons.auto_fix_off,
    ),
    BuiltinIconDefinition(
      id: 'design.scissors',
      label: 'Scissors',
      category: design,
      icon: Icons.content_cut,
    ),
    BuiltinIconDefinition(
      id: 'design.crop',
      label: 'Crop',
      category: design,
      icon: Icons.crop,
    ),
    BuiltinIconDefinition(
      id: 'design.eyedropper',
      label: 'Eyedropper',
      category: design,
      icon: Icons.colorize,
    ),
    BuiltinIconDefinition(
      id: 'design.fill',
      label: 'Fill',
      category: design,
      icon: Icons.format_color_fill,
    ),
    BuiltinIconDefinition(
      id: 'design.text',
      label: 'Text',
      category: design,
      icon: Icons.text_fields,
    ),
    BuiltinIconDefinition(
      id: 'design.shape',
      label: 'Shape',
      category: design,
      icon: Icons.category_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.rectangle',
      label: 'Rectangle',
      category: design,
      icon: Icons.rectangle_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.circle',
      label: 'Circle',
      category: design,
      icon: Icons.circle_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.lasso',
      label: 'Lasso',
      category: design,
      icon: Icons.gesture,
    ),
    BuiltinIconDefinition(
      id: 'design.magicWand',
      label: 'Magic Wand',
      category: design,
      icon: Icons.auto_fix_high,
    ),
    BuiltinIconDefinition(
      id: 'design.hand',
      label: 'Hand',
      category: design,
      icon: Icons.pan_tool_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.layers',
      label: 'Layers',
      category: design,
      icon: Icons.layers_outlined,
    ),
    BuiltinIconDefinition(
      id: 'design.rotate',
      label: 'Rotate',
      category: design,
      icon: Icons.rotate_right,
    ),
    BuiltinIconDefinition(
      id: 'design.mirror',
      label: 'Mirror',
      category: design,
      icon: Icons.flip,
    ),
    BuiltinIconDefinition(
      id: 'cad.cursor',
      label: 'Cursor',
      category: cad,
      icon: Icons.near_me_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.sketch',
      label: 'Sketch',
      category: cad,
      icon: Icons.architecture,
    ),
    BuiltinIconDefinition(
      id: 'cad.line',
      label: 'Line',
      category: cad,
      icon: Icons.show_chart,
    ),
    BuiltinIconDefinition(
      id: 'cad.arc',
      label: 'Arc',
      category: cad,
      icon: Icons.rounded_corner,
    ),
    BuiltinIconDefinition(
      id: 'cad.circle',
      label: 'Circle',
      category: cad,
      icon: Icons.circle_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.rectangle',
      label: 'Rectangle',
      category: cad,
      icon: Icons.crop_square,
    ),
    BuiltinIconDefinition(
      id: 'cad.measure',
      label: 'Measure',
      category: cad,
      icon: Icons.straighten,
    ),
    BuiltinIconDefinition(
      id: 'cad.dimension',
      label: 'Dimension',
      category: cad,
      icon: Icons.space_bar,
    ),
    BuiltinIconDefinition(
      id: 'cad.extrude',
      label: 'Extrude',
      category: cad,
      icon: Icons.view_in_ar,
    ),
    BuiltinIconDefinition(
      id: 'cad.cut',
      label: 'Cut',
      category: cad,
      icon: Icons.content_cut,
    ),
    BuiltinIconDefinition(
      id: 'cad.fillet',
      label: 'Fillet',
      category: cad,
      icon: Icons.rounded_corner,
    ),
    BuiltinIconDefinition(
      id: 'cad.chamfer',
      label: 'Chamfer',
      category: cad,
      icon: Icons.change_history,
    ),
    BuiltinIconDefinition(
      id: 'cad.rotateView',
      label: 'Rotate View',
      category: cad,
      icon: Icons.threed_rotation,
    ),
    BuiltinIconDefinition(
      id: 'cad.pan',
      label: 'Pan',
      category: cad,
      icon: Icons.pan_tool_alt_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.zoom',
      label: 'Zoom',
      category: cad,
      icon: Icons.zoom_in,
    ),
    BuiltinIconDefinition(
      id: 'cad.isometric',
      label: 'Isometric View',
      category: cad,
      icon: Icons.view_in_ar_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.front',
      label: 'Front View',
      category: cad,
      icon: Icons.crop_portrait,
    ),
    BuiltinIconDefinition(
      id: 'cad.side',
      label: 'Side View',
      category: cad,
      icon: Icons.view_sidebar_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.top',
      label: 'Top View',
      category: cad,
      icon: Icons.crop_landscape,
    ),
    BuiltinIconDefinition(
      id: 'cad.cube',
      label: 'Cube',
      category: cad,
      icon: Icons.view_in_ar,
    ),
    BuiltinIconDefinition(
      id: 'cad.assembly',
      label: 'Assembly',
      category: cad,
      icon: Icons.account_tree_outlined,
    ),
    BuiltinIconDefinition(
      id: 'cad.rebuild',
      label: 'Rebuild',
      category: cad,
      icon: Icons.replay,
    ),
    BuiltinIconDefinition(
      id: 'device.keyboard',
      label: 'Keyboard',
      category: device,
      icon: Icons.keyboard,
    ),
    BuiltinIconDefinition(
      id: 'profile.web',
      label: 'Web',
      category: device,
      icon: Icons.language,
    ),
    BuiltinIconDefinition(
      id: 'profile.meetings',
      label: 'Zoom / Teams',
      category: device,
      icon: Icons.video_call_outlined,
    ),
    BuiltinIconDefinition(
      id: 'profile.custom',
      label: 'Custom Profile',
      category: device,
      icon: Icons.dashboard_customize_outlined,
    ),
    BuiltinIconDefinition(
      id: 'profile.community',
      label: 'Community',
      category: device,
      icon: Icons.groups_outlined,
    ),
  ];

  static final byId = {for (final entry in entries) entry.id: entry};

  static BuiltinIconDefinition? find(String? id) => byId[id];
}

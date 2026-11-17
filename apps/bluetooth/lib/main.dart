import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BluetoothLiteApp());

class BluetoothLiteApp extends StatelessWidget {
  const BluetoothLiteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LumiaKey Bluetooth Lite',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff527c68), brightness: Brightness.dark), useMaterial3: true, scaffoldBackgroundColor: const Color(0xff101820)),
    home: const LiteHome(),
  );
}

class LiteHost {
  const LiteHost(this.id, this.name, this.address);
  final String id, name, address;
  factory LiteHost.fromMap(Map<Object?, Object?> map) => LiteHost(map['id']?.toString() ?? '', map['name']?.toString() ?? 'Paired device', map['address']?.toString() ?? '');
}

class LocalShortcut {
  const LocalShortcut({required this.title, required this.keyCode, required this.modifiers});
  final String title, keyCode;
  final List<String> modifiers;
  Map<String,Object> toJson() => {'title': title, 'keyCode': keyCode, 'modifiers': modifiers};
  factory LocalShortcut.fromJson(Map<String,dynamic> json) {
    final title = json['title']; final keyCode = json['keyCode']; final rawModifiers = json['modifiers'];
    if (title is! String || title.trim().isEmpty || title.length > 40 || keyCode is! String || !_validKey(keyCode) || rawModifiers is! List || rawModifiers.length > 4 || rawModifiers.any((item) => item is! String || !_modifierNames.contains(item))) throw const FormatException('Invalid local shortcut');
    return LocalShortcut(title: title, keyCode: keyCode, modifiers: rawModifiers.cast<String>());
  }
  static const _modifierNames = {'LEFT_CTRL','LEFT_ALT','LEFT_SHIFT','LEFT_META'};
  static bool _validKey(String key) => RegExp(r'^(?:[A-Z]|[0-9]|F(?:[1-9]|1[0-2])|ENTER|ESC|ESCAPE|BACKSPACE|TAB|SPACE|LEFT|RIGHT|UP|DOWN|DELETE|HOME|END|PAGE_UP|PAGE_DOWN)$').hasMatch(key);
}

class LiteHome extends StatefulWidget {
  const LiteHome({super.key});
  @override
  State<LiteHome> createState() => _LiteHomeState();
}

class _LiteHomeState extends State<LiteHome> {
  static const channel = MethodChannel('smart_keys/hid');
  int page = 0;
  String status = 'registering';
  String? error;
  LiteHost? active;
  List<LiteHost> hosts = [];
  List<LocalShortcut> shortcuts = [];
  bool loading = true;
  final Set<String> pendingModifiers = {};
  double? lastX, lastY;

  @override
  void initState() { super.initState(); channel.setMethodCallHandler(_nativeUpdate); unawaited(_load()); unawaited(_refresh()); }
  Future<void> _nativeUpdate(MethodCall call) async { if (call.method == 'connectionSnapshotChanged' && call.arguments is Map) _apply(call.arguments as Map); }
  void _apply(Object? value) {
    if (value is! Map || !mounted) return;
    setState(() {
      status = value['status']?.toString() ?? 'unavailable'; error = value['error']?.toString();
      active = value['activeHost'] is Map ? LiteHost.fromMap((value['activeHost'] as Map).cast<Object?,Object?>()) : null;
      hosts = value['pairedHosts'] is List ? (value['pairedHosts'] as List).whereType<Map>().map((e) => LiteHost.fromMap(e.cast<Object?,Object?>())).toList() : [];
    });
  }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('lite.shortcuts');
      if (raw != null) {
        try { shortcuts = (jsonDecode(raw) as List).map((e) => LocalShortcut.fromJson((e as Map).cast<String,dynamic>())).toList(); }
        catch (_) { shortcuts = []; }
      }
    } catch (_) {
      shortcuts = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  Future<void> _refresh() async { try { _apply(await channel.invokeMethod<Object?>('refreshPairedHosts')); } on PlatformException catch (e) { if (mounted) setState(() => error = e.message ?? e.code); } catch (_) {} }
  Future<void> _command(String method, [Map<String,Object?>? args]) async {
    try { _apply(await channel.invokeMethod<Object?>(method, args)); }
    on PlatformException catch (e) { if (mounted) setState(() => error = e.message ?? e.code); }
    on MissingPluginException { if (mounted) setState(() => error = 'Bluetooth HID is available on Android 9 or newer.'); }
  }
  Future<void> _connect() async {
    await _command('requestBluetoothAccess'); await _refresh();
    if (!mounted) return;
    if (hosts.isEmpty) { await _command('makeDiscoverable'); await _refresh(); }
    if (!mounted || hosts.isEmpty) return;
    final selected = await showModalBottomSheet<LiteHost>(context: context, builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [const ListTile(title: Text('Choose a paired computer')), ...hosts.map((host) => ListTile(leading: const Icon(Icons.computer), title: Text(host.name), subtitle: Text(host.address), onTap: () => Navigator.pop(context, host)))])));
    if (selected != null) await _command('connect', {'address': selected.address});
  }
  Future<void> _send(Map<String,Object?> action) => _command('sendStep', action);
  Future<void> _key(String key, {List<String> modifiers = const []}) async {
    final effective = {...pendingModifiers, ...modifiers}.toList();
    if (pendingModifiers.isNotEmpty) setState(pendingModifiers.clear);
    await _send({'type':'keyboard','keyCode':key,'modifiers':effective});
  }
  void _toggleModifier(String name) => setState(() { pendingModifiers.contains(name) ? pendingModifiers.remove(name) : pendingModifiers.add(name); });
  Future<void> _consumer(String value) => _send({'type':'consumerControl','value':value});
  Future<void> _mouse(String type, String value) => _send({'type':type,'value':value});

  @override
  void dispose() { channel.setMethodCallHandler(null); super.dispose(); }

  Future<void> _replaceShortcuts(List<LocalShortcut> next) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lite.shortcuts', jsonEncode(next.map((e) => e.toJson()).toList()));
      if (mounted) setState(() => shortcuts = next);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this shortcut on the phone.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('LumiaKey', style: TextStyle(fontWeight: FontWeight.w700)), Text('BLUETOOTH LITE', style: TextStyle(fontSize: 11, letterSpacing: 1.5))]), actions: [IconButton(tooltip: 'Refresh paired devices', onPressed: _refresh, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        _connectionCard(),
        if (error != null) MaterialBanner(content: Text(error!), leading: const Icon(Icons.info_outline), actions: [TextButton(onPressed: () => setState(() => error = null), child: const Text('DISMISS'))]),
        Expanded(child: IndexedStack(index: page, children: [_keyboard(), _touchpad(), _media(), _shortcuts()])),
      ]),
      bottomNavigationBar: NavigationBar(selectedIndex: page, onDestinationSelected: (value) => setState(() => page = value), destinations: const [NavigationDestination(icon: Icon(Icons.keyboard_alt_outlined), label: 'Keys'), NavigationDestination(icon: Icon(Icons.touch_app_outlined), label: 'Mouse'), NavigationDestination(icon: Icon(Icons.music_note), label: 'Media'), NavigationDestination(icon: Icon(Icons.bolt), label: 'Shortcuts')]),
    );
  }
  Widget _connectionCard() => Card(margin: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Row(children: [Icon(active == null ? Icons.bluetooth_disabled : Icons.bluetooth_connected, color: active == null ? Colors.orangeAccent : Colors.lightGreenAccent), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(active?.name ?? _statusLabel(), style: const TextStyle(fontWeight: FontWeight.w600)), Text(active == null ? 'Pair a computer in Android Bluetooth settings' : 'Connected over Bluetooth HID', style: Theme.of(context).textTheme.bodySmall)])), if (active == null) FilledButton.tonal(onPressed: _connect, child: const Text('Connect')) else IconButton(tooltip: 'Disconnect', onPressed: () => _command('disconnect'), icon: const Icon(Icons.link_off))])));
  String _statusLabel() => switch (status) {'permissionRequired' => 'Bluetooth permission needed', 'bluetoothOff' => 'Bluetooth is off', 'connecting' => 'Connecting…', 'registering' => 'Starting Bluetooth HID…', 'unavailable' => 'Bluetooth HID unavailable', _ => 'Not connected'};
  Widget _keyboard() => Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Bluetooth keyboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    const SizedBox(height: 8),
    Wrap(spacing: 6, runSpacing: 2, children: [for (final item in const {'LEFT_CTRL':'Ctrl','LEFT_ALT':'Alt','LEFT_SHIFT':'Shift','LEFT_META':'Meta'}.entries) FilterChip(label: Text(item.value), selected: pendingModifiers.contains(item.key), onSelected: (_) => _toggleModifier(item.key))]),
    const SizedBox(height: 4),
    Expanded(child: SingleChildScrollView(child: Column(children: [
      for (final row in const ['1234567890','QWERTYUIOP','ASDFGHJKL','ZXCVBNM']) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final key in row.split('')) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: _keyButton(key)))])),
      Row(children: [Expanded(child: _wideKey('Tab', Icons.keyboard_tab, () => _key('TAB'))), Expanded(child: _wideKey('Esc', Icons.keyboard_return, () => _key('ESC'))), Expanded(child: _wideKey('Backspace', Icons.backspace_outlined, () => _key('BACKSPACE')))]),
      Row(children: [Expanded(flex: 2, child: _wideKey('Space', Icons.space_bar, () => _key('SPACE'))), Expanded(child: _wideKey('Enter', Icons.keyboard_return, () => _key('ENTER')))]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_wideKey('←', Icons.arrow_back, () => _key('LEFT')), _wideKey('↑', Icons.arrow_upward, () => _key('UP')), _wideKey('↓', Icons.arrow_downward, () => _key('DOWN')), _wideKey('→', Icons.arrow_forward, () => _key('RIGHT'))]),
      const Text('Modifiers apply to the next key. Tap any key to send it to the computer.'),
    ]))),
  ]));
  Widget _keyButton(String key) => FilledButton.tonal(onPressed: () => _key(key), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)));
  Widget _wideKey(String label, IconData icon, VoidCallback action) => Padding(padding: const EdgeInsets.all(4), child: OutlinedButton.icon(onPressed: action, icon: Icon(icon, size: 18), label: Text(label), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14))));
  Widget _touchpad() => Padding(padding: const EdgeInsets.all(16), child: Column(children: [const Align(alignment: Alignment.centerLeft, child: Text('Mouse & touchpad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))), const SizedBox(height: 12), Expanded(child: GestureDetector(onPanStart: (d) { lastX = d.localPosition.dx; lastY = d.localPosition.dy; }, onPanUpdate: (d) { final dx = d.localPosition.dx - (lastX ?? d.localPosition.dx); final dy = d.localPosition.dy - (lastY ?? d.localPosition.dy); lastX = d.localPosition.dx; lastY = d.localPosition.dy; if (dx.abs() + dy.abs() > 2) _mouse('mouseMove', '${(dx * 1.5).round()},${(dy * 1.5).round()}'); }, onTap: () => _mouse('mouseButton','LEFT'), onLongPress: () => _mouse('mouseButton','RIGHT'), child: Container(width: double.infinity, decoration: BoxDecoration(color: const Color(0xff1b2930), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xff455b5b))), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.touch_app, size: 40, color: Color(0xff9cc7ad)), SizedBox(height: 12), Text('Drag to move · tap to click · hold for right click')])))), const SizedBox(height: 14), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton.filledTonal(tooltip:'Left click', onPressed: () => _mouse('mouseButton','LEFT'), icon: const Icon(Icons.ads_click)), IconButton.filledTonal(tooltip:'Right click', onPressed: () => _mouse('mouseButton','RIGHT'), icon: const Icon(Icons.more_horiz)), IconButton.filledTonal(tooltip:'Scroll up', onPressed: () => _mouse('mouseWheel','WHEEL_UP'), icon: const Icon(Icons.keyboard_arrow_up)), IconButton.filledTonal(tooltip:'Scroll down', onPressed: () => _mouse('mouseWheel','WHEEL_DOWN'), icon: const Icon(Icons.keyboard_arrow_down))]) ]));
  Widget _media() => Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Media controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(height: 20), Wrap(alignment: WrapAlignment.center, runSpacing: 20, children: [_mediaButton('Previous', Icons.skip_previous, 'PREVIOUS_TRACK'), _mediaButton('Play / pause', Icons.play_arrow, 'PLAY_PAUSE'), _mediaButton('Next', Icons.skip_next, 'NEXT_TRACK'), _mediaButton('Volume down', Icons.volume_down, 'VOLUME_DOWN'), _mediaButton('Mute', Icons.volume_mute, 'MUTE'), _mediaButton('Volume up', Icons.volume_up, 'VOLUME_UP')]), const Spacer(), const Center(child: Text('Standard Bluetooth media controls.'))]));
  Widget _mediaButton(String label, IconData icon, String usage) => SizedBox(width: 88, child: Column(children: [IconButton.filledTonal(onPressed: () => _consumer(usage), icon: Icon(icon), iconSize: 30, padding: const EdgeInsets.all(20)), const SizedBox(height: 5), Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium)]));
  Widget _shortcuts() => loading ? const Center(child: CircularProgressIndicator()) : Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Expanded(child: Text('Local shortcuts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))), FilledButton.icon(onPressed: _editShortcut, icon: const Icon(Icons.add), label: const Text('Add'))]), const SizedBox(height: 4), const Text('Saved only on this phone. No account or sync.'), const SizedBox(height: 12), Expanded(child: shortcuts.isEmpty ? const Center(child: Text('Add a shortcut you use often.')) : ListView(children: [for (final shortcut in shortcuts) Card(child: ListTile(leading: const Icon(Icons.bolt), title: Text(shortcut.title), subtitle: Text('${shortcut.modifiers.map(_modifierLabel).join(' + ')}${shortcut.modifiers.isEmpty ? '' : ' + '}${shortcut.keyCode}'), onTap: () => _send({'type':'keyboard','keyCode':shortcut.keyCode,'modifiers':shortcut.modifiers}), trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') _editShortcut(shortcut); if (value == 'delete') { final next = [...shortcuts]..remove(shortcut); _replaceShortcuts(next); } }, itemBuilder: (_) => const [PopupMenuItem(value:'edit', child: Text('Edit')), PopupMenuItem(value:'delete', child: Text('Delete'))])))]))]));
  String _modifierLabel(String value) => switch(value) {'LEFT_CTRL' => 'Ctrl','LEFT_ALT' => 'Alt','LEFT_SHIFT' => 'Shift','LEFT_META' => 'Meta',_ => value};
  Future<void> _editShortcut([LocalShortcut? existing]) async {
    final result = await showDialog<LocalShortcut>(
      context: context,
      builder: (_) => _ShortcutEditor(existing: existing),
    );
    if (result != null) {
      final next = [...shortcuts];
      if (existing != null) { next[next.indexOf(existing)] = result; }
      else { next.add(result); }
      await _replaceShortcuts(next);
    }
  }

}


class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({this.existing});
  final LocalShortcut? existing;
  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final TextEditingController title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController key = TextEditingController(text: widget.existing?.keyCode ?? 'C');
  final Set<String> selected = {};
  static const modifierLabels = {'LEFT_CTRL':'Ctrl','LEFT_ALT':'Alt','LEFT_SHIFT':'Shift','LEFT_META':'Meta'};

  @override
  void initState() { super.initState(); selected.addAll(widget.existing?.modifiers ?? const []); }
  @override
  void dispose() { title.dispose(); key.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New shortcut' : 'Edit shortcut'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText:'Name')),
      TextField(controller: key, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText:'Key (A–Z, 0–9, Enter…)')),
      const SizedBox(height:8),
      Wrap(spacing: 4, children: [for (final item in modifierLabels.entries) FilterChip(label: Text(item.value), selected: selected.contains(item.key), onSelected: (on) => setState(() { on ? selected.add(item.key) : selected.remove(item.key); }))]),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        final t = title.text.trim(); final k = key.text.trim().toUpperCase();
        if (t.isNotEmpty && t.length <= 40 && LocalShortcut._validKey(k)) Navigator.pop(context, LocalShortcut(title:t,keyCode:k,modifiers:selected.toList()));
      }, child: const Text('Save')),
    ],
  );
}

import 'package:flutter/material.dart';

import '../app.dart';
import '../icons/icon_catalog.dart';
import '../models/config.dart';
import 'icon_picker_screen.dart';

class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late final TextEditingController nameController;
  late final TextEditingController applicationController;
  late ProfileConfig profile;
  late ButtonVisual icon;
  int? accentColor;
  bool initialized = false;

  static const accents = <int>[
    0xFF67E8F9,
    0xFF60A5FA,
    0xFFA78BFA,
    0xFFF472B6,
    0xFFFB7185,
    0xFFFBBF24,
    0xFF4ADE80,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    profile = SmartKeysScope.of(
      context,
    ).config.profiles.firstWhere((item) => item.id == widget.profileId);
    nameController = TextEditingController(text: profile.name);
    applicationController = TextEditingController(
      text: profile.targetApplication ?? '',
    );
    icon = profile.profileIcon;
    accentColor = profile.accentColor;
    initialized = true;
  }

  @override
  void dispose() {
    if (initialized) {
      nameController.dispose();
      applicationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definition = BuiltinIconCatalog.find(icon.value);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameController,
            autofocus: profile.name == 'New Profile',
            decoration: const InputDecoration(labelText: 'Profile name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: applicationController,
            decoration: const InputDecoration(
              labelText: 'Target application (optional)',
              helperText:
                  'Stored for future versions; V1 does not auto-switch.',
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Icon(
                definition?.icon ?? Icons.dashboard_customize_outlined,
              ),
            ),
            title: const Text('Profile icon'),
            subtitle: Text(definition?.label ?? 'None'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectIcon,
          ),
          const SizedBox(height: 18),
          Text('Accent color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: accents.map((color) {
              final selected = accentColor == color;
              return InkWell(
                onTap: () => setState(() => accentColor = color),
                borderRadius: BorderRadius.circular(30),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(color),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.black)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Each profile owns an independent copy of all 15 buttons and '
                'the navigation control configuration.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectIcon() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => IconPickerScreen(selectedId: icon.value),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      icon = selected.isEmpty
          ? const ButtonVisual()
          : icon.copyWith(type: VisualType.builtinIcon, value: selected);
    });
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile name cannot be empty')),
      );
      return;
    }
    await SmartKeysScope.of(context).updateProfileDetails(
      profile,
      name: name,
      targetApplication: applicationController.text.trim(),
      icon: icon,
      accentColor: accentColor,
    );
    if (mounted) Navigator.pop(context);
  }
}

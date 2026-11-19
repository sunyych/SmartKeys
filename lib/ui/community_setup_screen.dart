import 'dart:async';

import 'package:flutter/material.dart';

import '../data/community_setup_repository.dart';
import '../data/shortcut_community_client.dart';
import '../mobile_appearance.dart';

String communityProfessionLabel(BuildContext context, String id) {
  final english = communityProfessionTags[id] ?? id;
  return context.mobileText(english, switch (id) {
    'software_engineering' => '软件工程',
    'design' => '设计',
    'video_editing' => '视频剪辑',
    'office' => '办公室工作',
    'other' => '其他',
    _ => english,
  });
}

String communityExperienceLabel(BuildContext context, String id) {
  final english = communityExperienceLevels[id] ?? id;
  return context.mobileText(english, switch (id) {
    'beginner' => '入门',
    'intermediate' => '熟练',
    'advanced' => '高级',
    _ => english,
  });
}

class CommunitySetupGate extends StatefulWidget {
  const CommunitySetupGate({
    super.key,
    required this.repository,
    required this.child,
  });

  final CommunitySetupRepository repository;
  final Widget child;

  @override
  State<CommunitySetupGate> createState() => _CommunitySetupGateState();
}

class _CommunitySetupGateState extends State<CommunitySetupGate> {
  CommunitySetupPreferences? _preferences;
  bool _loading = true;
  bool _failed = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final preferences = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _finish() {
    if (mounted) setState(() => _complete = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_failed || _complete || _preferences?.completed == true) {
      return widget.child;
    }
    return CommunitySetupScreen(
      repository: widget.repository,
      initialPreferences: _preferences,
      onComplete: _finish,
    );
  }
}

class CommunitySetupScreen extends StatefulWidget {
  const CommunitySetupScreen({
    super.key,
    required this.repository,
    this.initialPreferences,
    this.onComplete,
    this.isReopen = false,
  });

  final CommunitySetupRepository repository;
  final CommunitySetupPreferences? initialPreferences;
  final VoidCallback? onComplete;
  final bool isReopen;

  @override
  State<CommunitySetupScreen> createState() => _CommunitySetupScreenState();
}

class _CommunitySetupScreenState extends State<CommunitySetupScreen> {
  String? _profession;
  String? _experience;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPreferences;
    if (initial != null) {
      _setPreferences(initial);
    } else {
      unawaited(_load());
    }
  }

  void _setPreferences(CommunitySetupPreferences preferences) {
    _profession = preferences.profession;
    _experience = preferences.experience;
    _loading = false;
  }

  Future<void> _load() async {
    try {
      final preferences = await widget.repository.load();
      if (!mounted) return;
      setState(() => _setPreferences(preferences));
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = context.mobileText(
          'Setup choices could not be loaded. You can still use the app.',
          '无法加载设置。你仍可以继续使用应用。',
        );
      });
    }
  }

  Future<void> _finish({required bool skip}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        CommunitySetupPreferences(
          completed: true,
          profession: skip ? null : _profession,
          experience: skip ? null : _experience,
        ),
      );
      _completeFlow();
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.mobileText(
          'Setup choices could not be saved. Sharing settings were not changed. No data was uploaded.',
          '无法保存设置。分享设置保持原样，数据没有上传。',
        );
      });
      if (widget.onComplete != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: MobileText(
              'Setup could not be saved. Sharing settings were not changed. No data was uploaded.',
              '无法保存设置。分享设置保持原样，数据没有上传。',
            ),
          ),
        );
        _completeFlow();
      }
    }
  }

  void _completeFlow() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _continueWithoutSaving() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const MobileText('Community setup', '社区设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const MobileText('Community setup', '社区设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              context.mobileText(
                'Help make shortcut rankings more useful',
                '让快捷键排行更实用',
              ),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const MobileText(
              'These details are optional and stay on this device. They are only included when you review and choose them for a contribution. This setup does not turn on sharing or upload anything.',
              '这些信息为选填项，存储在本设备上。你可以在预览贡献内容时选择是否附上。本设置不会开启分享或上传信息。',
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              key: const ValueKey('community-setup-profession'),
              initialValue: _profession ?? '',
              decoration: InputDecoration(
                labelText: context.mobileText('Profession', '职业'),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: MobileText('Prefer not to say', '不愿透露'),
                ),
                ...communityProfessionTags.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(communityProfessionLabel(context, entry.key)),
                  ),
                ),
              ],
              onChanged: _saving || _loadFailed
                  ? null
                  : (value) => setState(
                      () => _profession = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('community-setup-experience'),
              initialValue: _experience ?? '',
              decoration: InputDecoration(
                labelText: context.mobileText('Computer proficiency', '电脑熟练程度'),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: MobileText('Prefer not to say', '不愿透露'),
                ),
                ...communityExperienceLevels.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(communityExperienceLabel(context, entry.key)),
                  ),
                ),
              ],
              onChanged: _saving || _loadFailed
                  ? null
                  : (value) => setState(
                      () => _experience = value == null || value.isEmpty
                          ? null
                          : value,
                    ),
            ),
            const SizedBox(height: 20),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: MobileText(
                  'You will still preview each contribution batch and choose whether to share it.',
                  '每批贡献都会先预览，由你决定是否分享。',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              TextButton(
                onPressed: _saving ? null : _continueWithoutSaving,
                child: const MobileText('Continue without saving', '继续使用，不保存'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('community-setup-finish'),
              onPressed: _saving || _loadFailed
                  ? null
                  : () => _finish(skip: false),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const MobileText('Save and continue', '保存并继续'),
            ),
            TextButton(
              key: const ValueKey('community-setup-skip'),
              onPressed: _saving
                  ? null
                  : widget.isReopen
                  ? _continueWithoutSaving
                  : () => _finish(skip: true),
              child: widget.isReopen
                  ? const MobileText('Cancel', '取消')
                  : const MobileText('Skip for now', '暂时跳过'),
            ),
          ],
        ),
      ),
    );
  }
}

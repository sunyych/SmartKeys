import 'dart:async';

import 'package:flutter/material.dart';

import '../data/community_setup_repository.dart';
import '../data/shortcut_community_client.dart';

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
        _error =
            'Setup choices could not be loaded. You can still use the app.';
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
        _error =
            'Setup choices could not be saved. Sharing settings were not changed. No data was uploaded.';
      });
      if (widget.onComplete != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Setup could not be saved. Sharing settings were not changed. No data was uploaded.',
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
        appBar: AppBar(title: const Text('Community setup')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Community setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Help make shortcut rankings more useful',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'These details are optional and stay on this device. They are only included when you review and choose them for a contribution. This setup does not turn on sharing or upload anything.',
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              key: const ValueKey('community-setup-profession'),
              initialValue: _profession ?? '',
              decoration: const InputDecoration(labelText: 'Profession'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Prefer not to say'),
                ),
                ...communityProfessionTags.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
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
              decoration: const InputDecoration(
                labelText: 'Computer proficiency',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Prefer not to say'),
                ),
                ...communityExperienceLevels.entries.map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
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
                child: Text(
                  'You will still preview each contribution batch and choose whether to share it.',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              TextButton(
                onPressed: _saving ? null : _continueWithoutSaving,
                child: const Text('Continue without saving'),
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
                  : const Text('Save and continue'),
            ),
            TextButton(
              key: const ValueKey('community-setup-skip'),
              onPressed: _saving
                  ? null
                  : widget.isReopen
                  ? _continueWithoutSaving
                  : () => _finish(skip: true),
              child: Text(widget.isReopen ? 'Cancel' : 'Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}

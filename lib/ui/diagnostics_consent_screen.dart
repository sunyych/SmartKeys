import 'dart:async';
import 'package:flutter/material.dart';
import '../diagnostics/diagnostics_service.dart';
import '../mobile_appearance.dart';

class DiagnosticsConsentGate extends StatefulWidget {
  const DiagnosticsConsentGate({
    super.key,
    required this.diagnostics,
    required this.child,
  });
  final DiagnosticsService diagnostics;
  final Widget child;
  @override
  State<DiagnosticsConsentGate> createState() => _DiagnosticsConsentGateState();
}

class _DiagnosticsConsentGateState extends State<DiagnosticsConsentGate> {
  bool _continued = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.diagnostics.initialize());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.diagnostics,
    builder: (_, _) {
      if (!widget.diagnostics.loaded) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_continued ||
          widget.diagnostics.choice != DiagnosticChoice.undecided) {
        return widget.child;
      }
      return DiagnosticsConsentScreen(
        diagnostics: widget.diagnostics,
        onContinue: () => setState(() => _continued = true),
      );
    },
  );
}

class DiagnosticsConsentScreen extends StatefulWidget {
  const DiagnosticsConsentScreen({
    super.key,
    required this.diagnostics,
    required this.onContinue,
  });
  final DiagnosticsService diagnostics;
  final VoidCallback onContinue;
  @override
  State<DiagnosticsConsentScreen> createState() =>
      _DiagnosticsConsentScreenState();
}

class _DiagnosticsConsentScreenState extends State<DiagnosticsConsentScreen> {
  bool _saving = false;
  Future<void> _choose(bool share) async {
    setState(() => _saving = true);
    final saved = await widget.diagnostics.setSharing(share);
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) widget.onContinue();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('diagnostics-consent'),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.bug_report_outlined, size: 40),
                const SizedBox(height: 14),
                Text(
                  context.mobileText('Share error diagnostics?', '分享错误诊断信息？'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                const MobileText(
                  'Help improve LumiaKey by sharing sanitized error reports with our central service. Reports contain error categories, times, app version and repeat counts.',
                  '你可以向我们的服务分享去除敏感信息的错误报告，帮助改进 LumiaKey。报告包含错误类别、时间、应用版本和发生次数。',
                ),
                const SizedBox(height: 10),
                const MobileText(
                  'Reports never include key presses, shortcut names or combinations, input text, clipboard contents, audio, file paths or connection credentials. Network infrastructure can still observe requests.',
                  '报告不包含按键记录、快捷键名称或组合、输入文字、剪贴板内容、音频、文件路径或连接凭据。网络基础设施仍能观察到请求。',
                ),
                const SizedBox(height: 10),
                const MobileText(
                  'You can use the app without sharing. Only errors occurring after you allow sharing are eligible. Change your choice at any time in Error logs.',
                  '你可以继续使用应用而不分享。只有在允许分享后发生的错误才会报告。你可以随时在错误日志里更改选择。',
                ),
                if (widget.diagnostics.storageError != null ||
                    !widget.diagnostics.metadata.verified)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(widget.diagnostics.status),
                  ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('diagnostics-local-only'),
                      onPressed: _saving ? null : () => _choose(false),
                      child: const MobileText('Keep on this device', '仅保存在本设备'),
                    ),
                    FilledButton(
                      key: const ValueKey('diagnostics-allow'),
                      onPressed:
                          _saving || !widget.diagnostics.metadata.verified
                          ? null
                          : () => _choose(true),
                      child: const MobileText('Allow error sharing', '允许分享错误'),
                    ),
                    TextButton(
                      key: const ValueKey('diagnostics-not-now'),
                      onPressed: _saving ? null : widget.onContinue,
                      child: const MobileText('Not now', '暂不设置'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

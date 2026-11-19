import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:diagnostics_core/diagnostics_core.dart';
import '../diagnostics/diagnostics_service.dart';
import '../mobile_appearance.dart';

import '../services/companion_service.dart';

Future<void> showDesktopConnectionSheet(
  BuildContext context,
  CompanionService companion, {
  Future<String?> Function(BuildContext context)? scanConnectionCode,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: DesktopConnectionPanel(
          companion: companion,
          scanConnectionCode: scanConnectionCode,
        ),
      ),
    ),
  ),
);

/// Explicit same-network pairing UI for platforms without UDP discovery.
class DesktopConnectionPanel extends StatefulWidget {
  const DesktopConnectionPanel({
    super.key,
    required this.companion,
    this.scanConnectionCode,
  });

  final CompanionService companion;
  final Future<String?> Function(BuildContext context)? scanConnectionCode;

  @override
  State<DesktopConnectionPanel> createState() => _DesktopConnectionPanelState();
}

class _DesktopConnectionPanelState extends State<DesktopConnectionPanel> {
  final _code = TextEditingController();
  bool _connecting = false;
  bool _scanning = false;
  String? _localError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final service = widget.companion;
    if (service is! ManualCompanionConnection || _connecting) return;
    final manualConnection = service as ManualCompanionConnection;
    setState(() => _connecting = true);
    try {
      await manualConnection.connectManually(_code.text);
      if (mounted) setState(() => _localError = null);
    } catch (error) {
      if (mounted) setState(() => _localError = '$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning || _connecting) return;
    setState(() {
      _scanning = true;
      _localError = null;
    });
    try {
      final code = await (widget.scanConnectionCode ?? _openScanner)(context);
      if (code == null || !mounted) return;
      // This is the same strict parser and authenticated local connection path
      // as manual entry. QR values are never opened as links.
      _code.text = code;
      await _connect();
    } catch (error) {
      if (mounted) setState(() => _localError = '$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<String?> _openScanner(BuildContext context) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const DesktopConnectionScannerScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final manual = widget.companion is ManualCompanionConnection;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.companion.activeHost,
        widget.companion.syncStatus,
        widget.companion.errorMessage,
      ]),
      builder: (context, _) {
        final host = widget.companion.activeHost.value;
        final connected =
            host != null &&
            widget.companion.syncStatus.value == CompanionSyncStatus.ready;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LumiaKey Desktop',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? context.mobileText(
                          'Connected to ${host.name} (${host.address})',
                          '已连接 ${host.name}（${host.address}）',
                        )
                      : context.mobileText(
                          'Pair on the same Wi-Fi. Your microphone audio and speech recognition stay on this iPad; only final text is sent to Desktop.',
                          '请连接同一个 Wi-Fi 网络进行配对。麦克风音频和语音识别留在本设备，仅将识别完成的文字发送到电脑。',
                        ),
                ),
                if (defaultTargetPlatform == TargetPlatform.iOS)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: MobileText(
                      'On iPhone and iPad, LumiaKey Desktop is required to use apps and keyboard shortcuts.',
                      '在 iPhone 和 iPad 上使用应用和快捷键时，需要连接 LumiaKey Desktop。',
                    ),
                  ),
                if (manual && !connected) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('scan-desktop-pairing-code'),
                    onPressed: _scanning || _connecting ? null : _scan,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code_scanner),
                    label: const MobileText(
                      'Scan Desktop QR code',
                      '扫描桌面连接二维码',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const MobileText(
                    'Or enter the connection code manually.',
                    '也可以手动输入连接码。',
                  ),
                  TextField(
                    controller: _code,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: context.mobileText(
                        'Desktop connection code',
                        '桌面连接码',
                      ),
                      hintText: '192.168.1.20:45832 token',
                      helperText: context.mobileText(
                        'The code stays on this device and is sent only in the authentication header.',
                        '连接码保存在本设备上，仅通过身份验证请求头发送。',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _connecting
                            ? null
                            : () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (data?.text != null && mounted) {
                                  _code.text = data!.text!;
                                }
                              },
                        icon: const Icon(Icons.content_paste),
                        label: const MobileText('Paste code', '粘贴连接码'),
                      ),
                      FilledButton(
                        onPressed: _connecting ? null : _connect,
                        child: _connecting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const MobileText('Connect', '连接'),
                      ),
                    ],
                  ),
                ] else if (manual && connected) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () =>
                          (widget.companion as ManualCompanionConnection)
                              .disconnect(),
                      child: const MobileText('Disconnect', '断开连接'),
                    ),
                  ),
                ],
                if (widget.companion.errorMessage.value case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_localError case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DesktopConnectionScannerScreen extends StatefulWidget {
  const DesktopConnectionScannerScreen({super.key, this.cameraPreviewBuilder});

  /// Allows deterministic UI rendering in screenshot tests without opening a camera.
  final WidgetBuilder? cameraPreviewBuilder;

  @override
  State<DesktopConnectionScannerScreen> createState() =>
      _ConnectionScannerState();
}

class _ConnectionScannerState extends State<DesktopConnectionScannerScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );
  bool _handled = false;
  bool _appInForeground = true;
  String? _cameraError;
  bool _reportedCameraError = false;

  void _reportCameraFailure() {
    if (_reportedCameraError) return;
    _reportedCameraError = true;
    scheduleMicrotask(() {
      if (mounted) {
        DiagnosticsScope.maybeOf(
          context,
        )?.record(DiagnosticCode.platformUnavailable);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.cameraPreviewBuilder != null) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScanner(requestPermission: true));
    });
  }

  Future<void> _startScanner({bool requestPermission = false}) async {
    final scannerState = _controller.value;
    if (!mounted ||
        _handled ||
        scannerState.isStarting ||
        scannerState.isRunning ||
        (!requestPermission && !scannerState.hasCameraPermission)) {
      return;
    }
    try {
      await _controller.start();
      if (mounted && !_appInForeground) await _stopScanner();
    } catch (error) {
      _reportCameraFailure();
      if (mounted) setState(() => _cameraError = error.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_handled) return;
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      unawaited(_startScanner());
    } else {
      _appInForeground = false;
      final scannerState = _controller.value;
      if (scannerState.hasCameraPermission && scannerState.isRunning) {
        unawaited(_stopScanner());
      }
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _controller.stop();
    } catch (_) {
      // A denied or unavailable camera is already shown as a manual fallback.
    }
  }

  @override
  void dispose() {
    if (widget.cameraPreviewBuilder == null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (code == null) return;
    _handled = true;
    unawaited(_stopScanner());
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const MobileText('Scan Desktop QR code', '扫描桌面连接二维码'),
      leading: IconButton(
        tooltip: context.mobileText('Cancel scanning', '取消扫描'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: _cameraError != null
              ? const ConnectionScannerUnavailable()
              : widget.cameraPreviewBuilder?.call(context) ??
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) {
                        _reportCameraFailure();
                        return const ConnectionScannerUnavailable();
                      },
                    ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: MobileText(
            'Point your camera at the code shown in LumiaKey Desktop.',
            '请将相机对准 LumiaKey Desktop 显示的二维码。',
          ),
        ),
      ],
    ),
  );
}

class ConnectionScannerUnavailable extends StatelessWidget {
  const ConnectionScannerUnavailable({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: MobileText(
        'Camera unavailable. Allow camera access to scan, or close this screen and enter the code manually.',
        '相机不可用。请允许相机访问后扫描，或关闭此页面并手动输入连接码。',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

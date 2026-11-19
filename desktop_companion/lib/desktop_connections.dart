import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'companion_server.dart';
import 'desktop_controller.dart';
import 'desktop_localizations.dart';

bool isPrivateDesktopIpv4(String value) {
  final address = InternetAddress.tryParse(value);
  if (address == null || address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

Future<List<String>> _listDesktopIpv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  return [
    for (final interface in interfaces)
      for (final address in interface.addresses) address.address,
  ];
}

class DesktopConnectionsPage extends StatelessWidget {
  const DesktopConnectionsPage({
    super.key,
    required this.controller,
    required this.server,
    this.statusCard,
    this.loadAddresses = _listDesktopIpv4Addresses,
  });

  final DesktopController controller;
  final CompanionServer server;
  final Widget? statusCard;
  final Future<List<String>> Function() loadAddresses;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (statusCard case final card?) ...[
                card,
                const SizedBox(height: 24),
              ],
              _PairingCard(
                controller: controller,
                server: server,
                loadAddresses: loadAddresses,
              ),
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.bluetooth_connected),
                      title: Text(
                        desktopText(context, 'Bluetooth HID', '蓝牙 HID'),
                      ),
                      subtitle: Text(
                        desktopText(
                          context,
                          'The Android phone pairs directly with this computer for keyboard and mouse input.',
                          'Android 手机可直接与此电脑配对，发送键盘和鼠标输入。',
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.sync),
                      title: Text(
                        desktopText(context, 'Desktop layout sync', '桌面布局同步'),
                      ),
                      subtitle: Text(
                        server.running
                            ? desktopText(
                                context,
                                'Authenticated local channel active on port ${server.actionPort ?? '—'}',
                                '已在端口 ${server.actionPort ?? '—'} 启用已认证的本地通道。',
                              )
                            : server.error ??
                                  desktopText(context, 'Not running', '未运行'),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_android),
                      title: Text(
                        desktopText(
                          context,
                          'Current Connected Phone',
                          '当前连接的手机',
                        ),
                      ),
                      subtitle: Text(
                        controller.connectedPhone ??
                            desktopText(
                              context,
                              'Waiting for LumiaKey Android',
                              '正在等待 LumiaKey Android 连接',
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _PairingCard extends StatefulWidget {
  const _PairingCard({
    required this.controller,
    required this.server,
    required this.loadAddresses,
  });

  final DesktopController controller;
  final CompanionServer server;
  final Future<List<String>> Function() loadAddresses;

  @override
  State<_PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends State<_PairingCard> {
  List<String> _addresses = const [];
  String? _address;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final saved = await widget.controller.pairingAddressStore.load();
      final addresses =
          (await widget.loadAddresses())
              .where(isPrivateDesktopIpv4)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _address = saved ?? addresses.firstOrNull;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _refresh() {
    if (_loading || _saving) return;
    setState(() {
      _loading = true;
      _saveFailed = false;
    });
    unawaited(_load());
  }

  Future<void> _select(String? address) async {
    if (_loading ||
        _loadFailed ||
        _saving ||
        address == null ||
        !_addresses.contains(address)) {
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.controller.pairingAddressStore.save(address);
      if (mounted) setState(() => _address = address);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            desktopText(
              context,
              'Private connection code copied. Treat it like a password.',
              '已复制私密连接码。请像保护密码一样保护它。',
            ),
          ),
        ),
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            desktopText(
              context,
              'Could not copy the connection code.',
              '无法复制连接码。',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSelect = !_loading && !_loadFailed && !_saving;
    final address = _address;
    final available = address != null && _addresses.contains(address);
    final port = widget.server.actionPort;
    final code = canSelect && available && widget.server.running && port != null
        ? desktopPairingCode(address, port, widget.server.token)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    desktopText(
                      context,
                      'Connect an iPhone, iPad, or Android device',
                      '连接 iPhone、iPad 或 Android 设备',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('desktop-pairing-refresh'),
                  tooltip: desktopText(
                    context,
                    'Refresh network addresses',
                    '刷新网络地址',
                  ),
                  onPressed: _loading || _saving ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              desktopText(
                context,
                'Join the same Wi-Fi, then scan this code in LumiaKey or paste the private connection code manually.',
                '请连接同一 Wi-Fi，然后在 LumiaKey 中扫码，或手动粘贴私密连接码。',
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              Text(
                desktopText(
                  context,
                  'Checking network addresses…',
                  '正在检查网络地址…',
                ),
              )
            else if (_loadFailed)
              Text(
                desktopText(
                  context,
                  'Could not load the network addresses. Refresh to try again.',
                  '无法读取网络地址。请刷新后重试。',
                ),
              )
            else ...[
              if (address != null && !available)
                Text(
                  desktopText(
                    context,
                    'Saved address $address is unavailable. Refresh or choose another address.',
                    '已保存的地址 $address 当前不可用。请刷新或选择其他地址。',
                  ),
                  key: const ValueKey('desktop-pairing-unavailable'),
                ),
              if (_addresses.isEmpty && address == null)
                Text(
                  desktopText(
                    context,
                    'No private IPv4 address is available.',
                    '没有可用的私有 IPv4 地址。',
                  ),
                ),
              if (_addresses.isNotEmpty) ...[
                InputDecorator(
                  isEmpty: !available,
                  decoration: InputDecoration(
                    labelText: desktopText(
                      context,
                      'Desktop network address',
                      '桌面网络地址',
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('desktop-pairing-address'),
                      isExpanded: true,
                      value: available ? address : null,
                      hint: Text(
                        desktopText(context, 'Choose an address', '选择地址'),
                      ),
                      items: [
                        for (final address in _addresses)
                          DropdownMenuItem(
                            value: address,
                            child: Text(address),
                          ),
                      ],
                      onChanged: canSelect ? _select : null,
                    ),
                  ),
                ),
                Text(
                  desktopText(
                    context,
                    'Choose the local address reachable by your phone or tablet. Avoid VPN and virtual adapter addresses.',
                    '请选择手机或平板可访问的局域网地址，避免使用 VPN 或虚拟网卡地址。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (_saveFailed)
              Text(
                desktopText(
                  context,
                  'Could not save the network address. Try again.',
                  '无法保存网络地址。请重试。',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            if (code != null)
              DesktopPairingQr(code: code)
            else if (!widget.server.running || port == null)
              Text(
                desktopText(
                  context,
                  'Start LumiaKey Desktop to generate a pairing code.',
                  '启动 LumiaKey Desktop 后才能生成配对码。',
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('desktop-pairing-copy'),
              onPressed: code == null ? null : () => _copy(code),
              icon: const Icon(Icons.copy),
              label: Text(
                desktopText(context, 'Copy connection code', '复制连接码'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String desktopPairingCode(String address, int port, String token) =>
    '$address:$port $token';

class DesktopPairingQr extends StatelessWidget {
  const DesktopPairingQr({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            desktopText(
              context,
              'Scan with LumiaKey on your phone',
              '用手机上的 LumiaKey 扫码',
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = constraints.maxWidth.isFinite
                  ? (constraints.maxWidth - 32).clamp(0.0, 220.0)
                  : 220.0;
              return DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: code,
                    size: qrSize,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    semanticsLabel: desktopText(
                      context,
                      'Private LumiaKey Desktop pairing QR code',
                      'LumiaKey Desktop 私密配对二维码',
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

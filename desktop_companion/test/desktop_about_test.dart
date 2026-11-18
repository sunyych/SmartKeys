import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/main.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _NoopDiscovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

Future<void> _openAbout(
  WidgetTester tester, {
  required Map<String, String> environment,
  required String version,
  required String build,
}) async {
  PackageInfo.setMockInitialValues(
    appName: 'LumiaKey',
    packageName: 'com.lumiaiq.smartkey',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1080, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final controller = DesktopController(
    store: MemoryDesktopConfigStore(),
    actions: DesktopActions(
      platformOverride: TargetPlatform.windows,
      environment: environment,
    ),
    discovery: _NoopDiscovery(),
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  await tester.pumpWidget(
    CompanionApp(controller: controller, startServer: false),
  );
  await tester.pump();
  await tester.tap(find.byIcon(Icons.info_outline));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('About shows packaged version, build and Rust selection', (
    tester,
  ) async {
    await _openAbout(
      tester,
      environment: const {'LUMIAKEY_DESKTOP_BACKEND': 'rust'},
      version: '9.4.1',
      build: '327',
    );
    expect(find.text('Version 9.4.1 (build 327)'), findsOneWidget);
    expect(find.text('Input backend: Rust (selected)'), findsOneWidget);
  });

  testWidgets('About shows a version alone and the shortcut-only selection', (
    tester,
  ) async {
    await _openAbout(
      tester,
      environment: const {'LUMIAKEY_WINDOWS_SHORTCUT_BACKEND': 'rust'},
      version: '9.4.1',
      build: '',
    );
    expect(find.text('Version 9.4.1'), findsOneWidget);
    expect(
      find.text('Input backend: Rust shortcuts (selected)'),
      findsOneWidget,
    );
  });

  testWidgets('About remains usable when package metadata is unavailable', (
    tester,
  ) async {
    await _openAbout(tester, environment: const {}, version: '', build: '');
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('Input backend: Standard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

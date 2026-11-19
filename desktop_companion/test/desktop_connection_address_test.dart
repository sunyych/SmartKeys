import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_companion/companion_server.dart';
import 'package:lumiakeys_companion/desktop_connections.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/desktop_pairing_address_store.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _PairingServer extends CompanionServer {
  _PairingServer({required super.controller}) {
    running = true;
  }

  @override
  int get actionPort => 45880;

  @override
  String get token => 'a' * 32;
}

class _Preferences extends Fake implements SharedPreferencesAsync {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class _FailingPairingStore extends MemoryDesktopPairingAddressStore {
  @override
  Future<void> save(String address) async =>
      throw StateError('Fixture storage failure');
}

const _address = ValueKey('desktop-pairing-address');
const _copy = ValueKey('desktop-pairing-copy');
const _refresh = ValueKey('desktop-pairing-refresh');
const _unavailable = ValueKey('desktop-pairing-unavailable');

DesktopController _controller(DesktopPairingAddressStore store) {
  final controller = DesktopController(
    store: MemoryDesktopConfigStore(),
    discovery: _Discovery(),
    pairingAddressStore: store,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _showPage(
  WidgetTester tester,
  DesktopController controller,
  Future<List<String>> Function() loadAddresses,
) async {
  final server = _PairingServer(controller: controller);
  addTearDown(server.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DesktopConnectionsPage(
          controller: controller,
          server: server,
          loadAddresses: loadAddresses,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _renderedCode(WidgetTester tester) =>
    tester.widget<DesktopPairingQr>(find.byType(DesktopPairingQr)).code;

void main() {
  test('only RFC1918 IPv4 addresses can become pairing choices', () {
    for (final address in [
      '10.8.0.2',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.5',
    ]) {
      expect(isPrivateDesktopIpv4(address), isTrue, reason: address);
    }
    for (final address in [
      '127.0.0.1',
      '169.254.1.1',
      '172.15.1.1',
      '172.32.1.1',
      '8.8.8.8',
      'fd00::24',
      '::ffff:192.168.1.5',
      'not-an-ip',
    ]) {
      expect(isPrivateDesktopIpv4(address), isFalse, reason: address);
    }
  });

  testWidgets(
    'choosing a network keeps the selection across page and controller restarts',
    (tester) async {
      final preferences = _Preferences();
      final store = SharedPreferencesDesktopPairingAddressStore(
        preferences: preferences,
      );
      final controller = _controller(store);
      var available = ['192.168.1.7', '8.8.8.8', '10.3.0.2', '10.3.0.2'];
      await _showPage(tester, controller, () async => available);
      expect(_renderedCode(tester), startsWith('10.3.0.2:45880 '));

      await tester.tap(find.byKey(_address));
      await tester.pumpAndSettle();
      expect(find.text('8.8.8.8'), findsNothing);
      await tester.tap(find.text('192.168.1.7').last);
      await tester.pumpAndSettle();
      expect(await store.load(), '192.168.1.7');
      expect(_renderedCode(tester), startsWith('192.168.1.7:45880 '));

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final clipboardWrites = <String>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.ensureVisible(find.byKey(_copy));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_copy));
      await tester.pumpAndSettle();
      expect(clipboardWrites.single, _renderedCode(tester));

      available = ['10.3.0.2', '192.168.1.7'];
      await tester.pumpWidget(const SizedBox.shrink());
      await _showPage(tester, controller, () async => available);
      expect(_renderedCode(tester), startsWith('192.168.1.7:45880 '));

      await tester.pumpWidget(const SizedBox.shrink());
      final reopened = _controller(
        SharedPreferencesDesktopPairingAddressStore(preferences: preferences),
      );
      await _showPage(tester, reopened, () async => available);
      expect(_renderedCode(tester), startsWith('192.168.1.7:45880 '));
    },
  );

  testWidgets(
    'a vanished address stays visible and never silently pairs another NIC',
    (tester) async {
      final store = MemoryDesktopPairingAddressStore();
      await store.save('192.168.1.8');
      var available = ['10.3.0.2'];
      await _showPage(tester, _controller(store), () async => available);

      expect(find.byKey(_unavailable), findsOneWidget);
      expect(find.textContaining('192.168.1.8'), findsOneWidget);
      expect(find.byType(DesktopPairingQr), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(_copy)).onPressed, isNull);
      expect(await store.load(), '192.168.1.8');

      available = ['10.3.0.2', '192.168.1.8'];
      await tester.tap(find.byKey(_refresh));
      await tester.pumpAndSettle();
      expect(find.byKey(_unavailable), findsNothing);
      expect(_renderedCode(tester), startsWith('192.168.1.8:45880 '));
    },
  );

  testWidgets(
    'a failed preference write keeps the last usable pairing choice',
    (tester) async {
      final store = _FailingPairingStore();
      await _showPage(
        tester,
        _controller(store),
        () async => ['10.3.0.2', '192.168.1.8'],
      );
      await tester.tap(find.byKey(_address));
      await tester.pumpAndSettle();
      await tester.tap(find.text('192.168.1.8').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save the network address. Try again.'),
        findsOneWidget,
      );
      expect(_renderedCode(tester), startsWith('10.3.0.2:45880 '));
      expect(await store.load(), isNull);
    },
  );
}

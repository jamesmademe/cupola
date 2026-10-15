import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/network_change.dart';

void main() {
  late String addresses;
  late bool unreadable;

  setUp(() {
    addresses = 'en0 192.168.1.50';
    unreadable = false;
  });

  /// Starts the watch over [addresses], with the first look read.
  Future<ProviderContainer> watching(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        networkAddressesReaderProvider.overrideWithValue(() async {
          if (unreadable) throw const SocketException('no interfaces');
          return addresses;
        }),
      ],
    );
    container.read(networkChangeWatchProvider);
    await tester.pump();
    return container;
  }

  int changes(ProviderContainer container) =>
      container.read(networkChangesProvider);

  testWidgets('the first look is not a change, and nothing moving says '
      'nothing', (tester) async {
    final c = await watching(tester);

    await tester.pump(networkLookInterval * 3);
    await tester.pump(networkSettle + networkSecondWord);
    expect(changes(c), 0);

    c.dispose();
  });

  testWidgets('Wi-Fi giving way to the mobile network is said once the '
      'addresses settle, and again for a VPN coming back', (tester) async {
    final c = await watching(tester);

    addresses = 'pdp_ip0 10.20.30.40';
    await tester.pump(networkLookInterval);
    await tester.pump();
    expect(changes(c), 0, reason: 'not before they settle');

    await tester.pump(networkSettle);
    expect(changes(c), 1);

    await tester.pump(networkSecondWord);
    expect(changes(c), 2);

    await tester.pump(networkLookInterval * 3);
    expect(changes(c), 2, reason: 'nothing moved since');

    c.dispose();
  });

  testWidgets('a switch made of several moves is said once, after the '
      'last', (tester) async {
    final c = await watching(tester);

    addresses = '';
    await tester.pump(networkLookInterval);
    await tester.pump();
    addresses = 'pdp_ip0 10.20.30.40';
    await tester.pump(networkLookInterval - const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(networkSettle);
    expect(changes(c), 1);

    c.dispose();
  });

  testWidgets('a look that cannot read the addresses says nothing', (
    tester,
  ) async {
    final c = await watching(tester);

    unreadable = true;
    await tester.pump(networkLookInterval);
    await tester.pump(networkSettle + networkSecondWord);
    expect(changes(c), 0);

    unreadable = false;
    await tester.pump(networkLookInterval);
    await tester.pump(networkSettle);
    expect(changes(c), 0, reason: 'the addresses are the ones before');

    c.dispose();
  });
}

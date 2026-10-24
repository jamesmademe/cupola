import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/data/pair_fetch.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/domain/pair_cipher.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final _loopback = InternetAddress.loopbackIPv4;

const _package = PairPackage(
  from: PairDevice.mac,
  connections: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://192.168.1.10:7878',
      credential: 'radarr-key',
    ),
  ],
);

Future<PairServer> _open({
  Duration lifetime = const Duration(minutes: 2),
  int maxWrongTries = 3,
}) async {
  final key = PairCipher.newKey();
  return PairServer.open(
    address: _loopback,
    key: key,
    sealed: await PairCipher.seal(key, _package.encode()),
    lifetime: lifetime,
    maxWrongTries: maxWrongTries,
  );
}

Future<int> _get(PairServer server, String path) async {
  final client = HttpClient();
  try {
    final request = await client.get(
      server.link.host.address,
      server.link.port,
      path,
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Matcher _failsWith(PairFetchFailure failure) => throwsA(
  isA<PairFetchException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  group('the server', () {
    test('hands the package over once, then closes', () async {
      final server = await _open();
      final package = await fetchPairPackage(server.link);
      expect(package.toJson(), _package.toJson());
      expect(server.ended.value, PairServerEnd.sent);
      await expectLater(
        fetchPairPackage(server.link),
        _failsWith(PairFetchFailure.unreachable),
      );
    });

    test('answers nothing but its one path, and closes on the third wrong '
        'try', () async {
      final server = await _open();
      expect(await _get(server, '/'), HttpStatus.notFound);
      expect(await _get(server, '/package'), HttpStatus.notFound);
      expect(server.ended.value, isNull);
      expect(await _get(server, '/x'), HttpStatus.notFound);
      expect(server.ended.value, PairServerEnd.refused);
      await expectLater(
        fetchPairPackage(server.link),
        _failsWith(PairFetchFailure.unreachable),
      );
    });

    test('closes when its time is up', () async {
      final server = await _open(lifetime: const Duration(milliseconds: 100));
      final ended = Completer<void>();
      server.ended.addListener(ended.complete);
      await ended.future;
      expect(server.ended.value, PairServerEnd.expired);
    });

    test('closes when asked, and stays closed', () async {
      final server = await _open();
      await server.close();
      expect(server.ended.value, PairServerEnd.closed);
      await server.close();
      expect(server.ended.value, PairServerEnd.closed);
    });

    test('tells its address and closing time in its link, never its key', () {
      return _open().then((server) async {
        expect(server.link.host, _loopback);
        expect(server.link.port, greaterThan(1023));
        expect(server.toString(), isNot(contains('key')));
        expect(
          server.link.closesAt.difference(DateTime.now()).inSeconds,
          inInclusiveRange(118, 120),
        );
        await server.close();
      });
    });
  });

  group('fetching', () {
    test('says an expired code is one without touching the network', () async {
      final server = await _open();
      await expectLater(
        fetchPairPackage(
          server.link,
          now: () => server.link.closesAt.add(const Duration(minutes: 1)),
        ),
        _failsWith(PairFetchFailure.expired),
      );
      expect(server.ended.value, isNull);
      await server.close();
    });

    test('says a code past its time that does not answer expired', () async {
      final server = await _open();
      await server.close();
      var calls = 0;
      await expectLater(
        fetchPairPackage(
          server.link,
          now: () => calls++ == 0
              ? DateTime.now()
              : server.link.closesAt.add(const Duration(minutes: 1)),
        ),
        _failsWith(PairFetchFailure.expired),
      );
    });

    test('says a package that does not open is unreadable', () async {
      final key = PairCipher.newKey(Random(3));
      final impostor = await HttpServer.bind(_loopback, 0);
      final path = await PairCipher.pathOf(key);
      impostor.listen((request) async {
        request.response.add(
          request.uri.path == path ? List.filled(64, 7) : const [],
        );
        await request.response.close();
      });
      addTearDown(() => impostor.close(force: true));
      final link = PairLink(
        host: _loopback,
        port: impostor.port,
        key: key,
        closesAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      await expectLater(
        fetchPairPackage(link),
        _failsWith(PairFetchFailure.unreadable),
      );
    });

    test('answers nothing to a code with another key', () async {
      final server = await _open();
      final stolen = PairLink(
        host: server.link.host,
        port: server.link.port,
        key: PairCipher.newKey(Random(4)),
        closesAt: server.link.closesAt,
      );
      await expectLater(
        fetchPairPackage(stolen),
        _failsWith(PairFetchFailure.unreachable),
      );
      await server.close();
    });
  });

  group('where the server stands', () {
    Future<List<NetworkInterface>> Function() lists(
      Map<String, String> addresses,
    ) =>
        () async => [
          for (final MapEntry(:key, :value) in addresses.entries)
            _Interface(key, [InternetAddress(value)]),
        ];

    test('on the Wi-Fi, never a VPN, a cellular link or a bridge', () async {
      expect(
        (await pairingAddress(
          interfaces: lists({
            'utun4': '10.8.0.2',
            'pdp_ip0': '10.120.4.9',
            'bridge100': '192.168.64.1',
            'en0': '192.168.1.20',
            'en5': '192.168.2.40',
          }),
        ))?.address,
        '192.168.1.20',
      );
    });

    test('on the wire when there is no Wi-Fi', () async {
      expect(
        (await pairingAddress(
          interfaces: lists({'eth0': '10.0.0.7', 'wg0': '10.9.0.1'}),
        ))?.address,
        '10.0.0.7',
      );
    });

    test('nowhere when the device is on no home network', () async {
      expect(
        await pairingAddress(
          interfaces: lists({
            'pdp_ip0': '10.120.4.9',
            'utun3': '100.74.92.3',
            'en0': '169.254.3.3',
          }),
        ),
        isNull,
      );
    });
  });
}

final class _Interface implements NetworkInterface {
  _Interface(this.name, List<InternetAddress> addresses)
    : addresses = [for (final address in addresses) _Address(address)];

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  int get index => 0;
}

final class _Address extends Fake implements InterfaceAddress {
  _Address(this._value);

  final InternetAddress _value;

  @override
  String get address => _value.address;

  @override
  InternetAddressType get type => _value.type;

  @override
  Uint8List get rawAddress => _value.rawAddress;

  @override
  bool get isLoopback => _value.isLoopback;
}

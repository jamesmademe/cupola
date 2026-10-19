import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';

NpmProxyHost _host({
  required int id,
  required String domain,
  String forwardHost = 'backend.lan',
  int port = 8080,
  bool enabled = true,
  bool configLoaded = true,
}) {
  return NpmProxyHost.fromJson({
    'id': id,
    'domain_names': [domain],
    'forward_scheme': 'http',
    'forward_host': forwardHost,
    'forward_port': port,
    'enabled': enabled,
    'meta': {'nginx_online': configLoaded},
  });
}

void main() {
  group('NpmUpstreamProbe', () {
    test('a host outside the budget is unchecked, never down', () async {
      // The distinction the whole enum exists for: a row nobody measured must
      // not read as a row that failed.
      final hosts = List.generate(
        5,
        (i) => _host(id: i, domain: 'host$i.example.net'),
      );
      final probe = NpmUpstreamProbe(
        budget: 2,
        connector: (_, _, _) async => true,
      );

      final report = await probe.run(hosts);

      expect(report.checked, 2);
      expect(report.total, 5);
      expect(report.forHost(hosts.last.id), NpmUpstream.unchecked);
      // The word `enabled` is part of the sentence: the total is the probe's
      // own population, and it is printed beside a header count of the whole
      // host table.
      expect(report.coverage, '2 of 5 enabled checked from this device');
    });

    test(
      'a disabled host is not probed: nothing is being served through it',
      () async {
        final probed = <String>[];
        final probe = NpmUpstreamProbe(
          connector: (host, _, _) async {
            probed.add(host);
            return true;
          },
        );

        final report = await probe.run([
          _host(
            id: 1,
            domain: 'off.example.net',
            forwardHost: 'a',
            enabled: false,
          ),
          _host(id: 2, domain: 'on.example.net', forwardHost: 'b'),
        ]);

        expect(probed, ['b']);
        expect(report.forHost(1), NpmUpstream.unchecked);
        expect(
          report.total,
          1,
          reason: 'a disabled host is not a coverage gap',
        );
      },
    );

    test('the budget goes to the hosts nginx already refused', () async {
      final probed = <String>[];
      final probe = NpmUpstreamProbe(
        budget: 1,
        connector: (host, _, _) async {
          probed.add(host);
          return true;
        },
      );

      await probe.run([
        _host(id: 1, domain: 'aaa.example.net', forwardHost: 'healthy'),
        _host(
          id: 2,
          domain: 'zzz.example.net',
          forwardHost: 'broken',
          configLoaded: false,
        ),
      ]);

      // Alphabetically last, but it is the row the user opened the screen for.
      expect(probed, ['broken']);
    });

    test('a connector that throws is a verdict, not a crash', () async {
      final probe = NpmUpstreamProbe(
        connector: (_, _, _) async => throw StateError('no route to host'),
      );

      final report = await probe.run([_host(id: 1, domain: 'a.example.net')]);

      expect(report.forHost(1), NpmUpstream.down);
      expect(report.downCount, 1);
    });

    test(
      'a forward target that cannot be dialled is down without a socket',
      () async {
        var attempts = 0;
        final probe = NpmUpstreamProbe(
          connector: (_, _, _) async {
            attempts++;
            return true;
          },
        );

        final report = await probe.run([
          _host(id: 1, domain: 'a.example.net', forwardHost: '  '),
          _host(id: 2, domain: 'b.example.net', port: 0),
        ]);

        expect(attempts, 0);
        expect(report.forHost(1), NpmUpstream.down);
        expect(report.forHost(2), NpmUpstream.down);
      },
    );

    test('nothing checked prints no coverage line at all', () async {
      final probe = NpmUpstreamProbe(connector: (_, _, _) async => true);

      final report = await probe.run(const []);

      expect(report.coverage, isNull);
    });

    test(
      'a loopback forward host is never probed: from here it is this device',
      () async {
        final probed = <String>[];
        final probe = NpmUpstreamProbe(
          connector: (host, _, _) async {
            probed.add(host);
            return true;
          },
        );
        final loopbacks = [
          '127.0.0.1',
          '127.0.1.1',
          'localhost',
          'LOCALHOST',
          'app.localhost',
          '::1',
          '[::1]',
          '0.0.0.0',
        ];
        final hosts = [
          for (final (i, target) in loopbacks.indexed)
            _host(id: i, domain: 'h$i.example.net', forwardHost: target),
          _host(id: 99, domain: 'z.example.net', forwardHost: '10.0.0.5'),
        ];

        final report = await probe.run(hosts);

        expect(probed, ['10.0.0.5']);
        for (final (i, _) in loopbacks.indexed) {
          expect(report.forHost(i), NpmUpstream.unchecked);
        }
        // Unchecked inside the total, like a host outside the budget: the
        // coverage line still counts them as hosts nobody measured.
        expect(report.coverage, '1 of 9 enabled checked from this device');
      },
    );

    test('a loopback host does not spend the budget', () async {
      final probe = NpmUpstreamProbe(
        budget: 1,
        connector: (_, _, _) async => true,
      );

      final report = await probe.run([
        _host(id: 1, domain: 'a.example.net', forwardHost: '127.0.0.1'),
        _host(id: 2, domain: 'b.example.net', forwardHost: 'nas.lan'),
      ]);

      expect(report.forHost(2), NpmUpstream.answering);
    });
  });
}

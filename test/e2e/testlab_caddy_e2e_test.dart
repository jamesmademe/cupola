@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

/// The lab's edge, read by the app's own code.
///
/// Caddy stands in front of three services, each origin with a certificate of
/// its own, issued by Caddy's internal CA. The app reads the fingerprint,
/// pins it, and the pin is what lets the connection through; when the lab
/// throws the internal CA away and starts the Caddy again, the old pin must
/// stop working and the new one must work. That is the rotation the flow
/// catalogue asks for (I-22).
///
/// The edge is a service of the lab, up only while the `caddy-edge` scenario
/// is applied, which this suite does for itself:
///
///     python3 test/e2e/testlab/testlab.py scenario apply caddy-edge
///
/// Then:
///
///     export CUPOLA_TESTLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_testlab/state/credentials.env"
///     flutter test test/e2e/testlab_caddy_e2e_test.dart --tags e2e --run-skipped
///
/// The credentials file supplies the Dockge login the edge's origin needs.
class _Origin {
  const _Origin({required this.key, required this.host, required this.port});

  final String key;
  final String host;
  final int port;

  String get url => 'https://$host:$port';
}

/// The three origins of the edge, one port each: the app pins a host, a port
/// and a fingerprint, so three origins need three addresses of their own.
const _origins = <_Origin>[
  _Origin(key: 'radarr', host: 'radarr.localhost', port: 8445),
  _Origin(key: 'dockge', host: 'dockge.localhost', port: 8446),
  _Origin(key: 'truenas', host: 'truenas.localhost', port: 8447),
];

/// The lab's credentials, read once: the Dockge login needs them, and the
/// helpers below cannot reach a local variable of [main].
final Map<String, String> credentials = _loadCredentials();

void main() {
  setUpAll(() async {
    await _scenario('apply', 'caddy-edge');
  });

  tearDownAll(() async {
    await _scenario('teardown', 'caddy-edge');
  });

  test(
    'the edge answers on three origins with a certificate of its own',
    () async {
      final fingerprints = <String, String>{};
      for (final origin in _origins) {
        final certificate = await probeServerCertificate(
          origin.host,
          origin.port,
        );
        expect(
          certificate,
          isNotNull,
          reason: 'the ${origin.key} origin has no certificate',
        );
        expect(
          certificate!.fingerprint,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'the fingerprint is the SHA-256 of the certificate',
        );
        fingerprints[origin.key] = certificate.fingerprint;
      }
      expect(
        fingerprints,
        hasLength(_origins.length),
        reason:
            'the app pins the certificate that failed platform verification: '
            'one CA intermediate serves the edge\'s three leaves, so the '
            'three pins are the same value on three different origins',
      );
    },
  );

  test(
    'the pin the app reads is the pin that lets the request through',
    () async {
      for (final origin in _origins) {
        final certificate = await probeServerCertificate(
          origin.host,
          origin.port,
        );
        expect(certificate, isNotNull);
        final answer = await _call(origin, certificate!.fingerprint);
        expect(
          answer,
          isNotEmpty,
          reason: 'the ${origin.key} origin answered nothing',
        );
      }
    },
  );

  test(
    'after the rotation the old pin is refused and the new one works',
    () async {
      final before = <String, String>{};
      final leavesBefore = <String, String>{};
      for (final origin in _origins) {
        final certificate = await probeServerCertificate(
          origin.host,
          origin.port,
        );
        expect(certificate, isNotNull);
        before[origin.key] = certificate!.fingerprint;
        leavesBefore[origin.key] = await _leaf(origin);
      }

      final leavesAfter = await _rotate();

      // The pin the app reads is the certificate that failed verification,
      // which for a chained server is the CA intermediate, not the leaf. The
      // lab's own reading watches the leaf: one different certificate per
      // origin, and a new one after the rotation.
      final after = <String, String>{};
      for (final origin in _origins) {
        expect(
          leavesAfter[origin.key],
          isNot(leavesBefore[origin.key]),
          reason: 'the ${origin.key} certificate did not change',
        );
        final certificate = await probeServerCertificate(
          origin.host,
          origin.port,
        );
        expect(certificate, isNotNull);
        after[origin.key] = certificate!.fingerprint;
      }

      for (final origin in _origins) {
        expect(
          after[origin.key],
          isNot(before[origin.key]),
          reason: 'the ${origin.key} pin did not change',
        );
        await expectLater(
          _call(origin, before[origin.key]!),
          throwsA(
            predicate<Object>(
              (error) =>
                  classifyConnectionFailure(error) == ServiceFailureReason.tls,
              'a certificate the app does not trust',
            ),
          ),
          reason: 'the ${origin.key} origin still accepted the old pin',
        );
        final answer = await _call(origin, after[origin.key]!);
        expect(
          answer,
          isNotEmpty,
          reason: 'the new pin did not open the ${origin.key} origin',
        );
      }
    },
  );
}

/// Asks one origin for something, with [pin] as the only certificate the
/// client is allowed to accept. Answers what the origin said, so the caller
/// can tell an answer from a silence.
Future<String> _call(_Origin origin, String pin) async {
  switch (origin.key) {
    case 'radarr':
      final client = ApiClient(
        baseUrl: origin.url,
        apiKey: 'test-key',
        pinnedCertFingerprint: pin,
      );
      addTearDown(client.close);
      final response = await client.get('/api/v3/system/status');
      final status = response.data;
      expect(status, isA<Map>());
      return '${(status as Map)['appName']}';
    case 'dockge':
      final client = DockgeClient(
        baseUrl: origin.url,
        username: credentials['CUPOLA_TESTLAB_DOCKGE_USERNAME'],
        password: credentials['CUPOLA_TESTLAB_DOCKGE_PASSWORD'],
        certFingerprint: pin,
      );
      addTearDown(client.close);
      // The stack list is what Dockge pushes over the authenticated session:
      // the version field is optional and this Dockge leaves it out.
      final stacks = await DockgeService(client).fetchStacks();
      expect(stacks, isA<List>());
      return '${stacks.length} stacks';
    case 'truenas':
      final client = TrueNasWsClient(
        baseUrl: origin.url,
        apiKey: 'test-key',
        certFingerprint: pin,
      );
      addTearDown(client.close);
      expect(await TrueNasService(client).ping(), isTrue);
      return 'core.ping';
  }
  throw StateError('the edge has no origin named ${origin.key}');
}

/// The certificate the server actually serves, read from the socket: the
/// leaf. The app's trust prompt reads [probeServerCertificate] instead, which
/// is the certificate platform verification rejected (the CA intermediate for
/// a chained server).
Future<String> _leaf(_Origin origin) async {
  final socket = await SecureSocket.connect(
    origin.host,
    origin.port,
    onBadCertificate: (_) => true,
  );
  try {
    final certificate = socket.peerCertificate;
    if (certificate == null) fail('${origin.key} served no leaf certificate');
    return certificateFingerprint(certificate);
  } finally {
    socket.destroy();
  }
}

/// Throws the internal CA away and starts the Caddy again. Answers the
/// fingerprints the origins present after the rotation.
Future<Map<String, String>> _rotate() async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/caddy_lab.py',
    '--rotate',
  ], workingDirectory: Directory.current.path);
  expect(
    result.exitCode,
    0,
    reason: 'the lab could not rotate the certificates: ${result.stderr}',
  );
  final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  return payload.map((key, value) => MapEntry(key, value as String));
}

/// Applies or tears down a scenario through the lab's own control plane.
Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name answered ${result.exitCode}: '
      '${result.stdout}${result.stderr}',
    );
  }
}

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_TESTLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/scratch/zz_testlab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing testlab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}

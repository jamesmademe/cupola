@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';

/// The lab's edge, read by the app's own code.
///
/// The edge is a self-signed origin in front of Radarr, so the app meets a
/// certificate of its own: it reads the fingerprint, pins it, and the pin is
/// what lets the connection through. When the lab makes a new certificate, the
/// old pin must stop working and the new one must work, which is the rotation
/// the flow catalogue asks for.
void main() {
  const edge = 'https://127.0.0.1:8444';

  Future<String> rotate() async {
    final result = await Process.run('python3', [
      'test/e2e/testlab/edge_lab.py',
      '--rotate',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason: 'the lab could not rotate the certificate: ${result.stderr}',
    );
    final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return payload['fingerprint'] as String;
  }

  test('the edge answers with a certificate the app can pin', () async {
    final certificate = await probeServerCertificate('127.0.0.1', 8444);
    expect(certificate, isNotNull, reason: 'the edge has no certificate');
    expect(
      certificate!.fingerprint,
      matches(RegExp(r'^[0-9a-f]{64}$')),
      reason: 'the fingerprint is the SHA-256 of the certificate',
    );

    final client = ApiClient(
      baseUrl: edge,
      apiKey: 'test-key',
      pinnedCertFingerprint: certificate.fingerprint,
    );
    addTearDown(client.close);
    final response = await client.get('/api/v3/system/status');
    expect(response.data, isA<Map>());
  });

  test(
    'after the rotation the old pin is refused and the new one works',
    () async {
      final before = await probeServerCertificate('127.0.0.1', 8444);
      expect(before, isNotNull);

      final after = await rotate();
      expect(
        after,
        isNot(before!.fingerprint),
        reason: 'the certificate did not change',
      );

      final pinned = ApiClient(
        baseUrl: edge,
        apiKey: 'test-key',
        pinnedCertFingerprint: before.fingerprint,
      );
      addTearDown(pinned.close);
      Object? error;
      try {
        await pinned.get('/api/v3/system/status');
      } catch (failure) {
        error = failure;
      }
      expect(error, isNotNull, reason: 'the old pin was still accepted');
      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.tls,
        reason: 'a certificate the app does not trust is a certificate fault',
      );

      final client = ApiClient(
        baseUrl: edge,
        apiKey: 'test-key',
        pinnedCertFingerprint: after,
      );
      addTearDown(client.close);
      final response = await client.get('/api/v3/system/status');
      expect(response.data, isA<Map>());
    },
  );
}

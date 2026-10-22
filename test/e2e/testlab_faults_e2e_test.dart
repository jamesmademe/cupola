@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The lab's fault classes, read by the app's own code.
///
/// Every service sits behind the Toxiproxy the lab keeps, so a fault is a toxic
/// on the proxy the app talks to. This suite asks the app's client to read the
/// four classes and says what the app would draw, with the app's own words
/// from `connection_failure.dart`: the red "did not answer", the amber "was
/// reached but did not reply in time", the flapping link, and the service that
/// only works at home.
void main() {
  // The proxy in front of Radarr, and the away address on the same upstream.
  const proxy = 'http://127.0.0.1:27878';
  const away = 'http://127.0.0.1:27879';

  Future<void> fault(String mode, [String? milliseconds]) async {
    final result = await Process.run('python3', [
      'test/e2e/testlab/testlab.py',
      'fault',
      'radarr',
      mode,
      ?milliseconds,
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'the lab refused the fault: ${result.stdout}${result.stderr}',
    );
  }

  Future<Object?> probe(
    String base, {
    bool onlyAtHome = false,
    Duration? receiveTimeout = const Duration(seconds: 2),
  }) async {
    final client = ApiClient(
      baseUrl: base,
      apiKey: 'test-key',
      onlyAtHome: onlyAtHome ? ServiceKey.radarr : null,
    );
    try {
      await client.get('/api/v3/system/status', receiveTimeout: receiveTimeout);
      return null;
    } catch (error) {
      return error;
    } finally {
      client.close();
    }
  }

  test('a service that drops the connection did not answer', () async {
    await fault('down');
    final error = await probe(proxy);
    expect(error, isNotNull, reason: 'the fault did not reach the proxy');

    final reason = classifyConnectionFailure(error);
    expect(reason, ServiceFailureReason.unreachable);
    expect(failureHeadline(reason, subject: 'Radarr'), 'Radarr did not answer');

    await fault('clear');
    expect(await probe(proxy), isNull, reason: 'the service did not come back');
  });

  test('a connection that dies mid-flight is still a failure', () async {
    await fault('timeout');
    final error = await probe(proxy);
    expect(error, isNotNull);
    expect(
      classifyConnectionFailure(error),
      isNot(ServiceFailureReason.unknown),
      reason: 'a broken connection is a known failure, not a mystery',
    );
    await fault('clear');
  });

  test(
    'a service that answers too late was reached but did not reply',
    () async {
      await fault('slow', '4000');
      final error = await probe(proxy);
      expect(error, isNotNull);

      final reason = classifyConnectionFailure(error);
      expect(reason, ServiceFailureReason.timeout);
      expect(
        failureHeadline(reason, subject: 'Radarr'),
        'Radarr was reached but did not reply in time',
      );

      await fault('clear');
      expect(await probe(proxy), isNull);
    },
  );

  test('a link that flaps fails and then comes back', () async {
    await fault('flap');
    final outcomes = <Object?>[
      for (var attempt = 0; attempt < 6; attempt++) await probe(proxy),
    ];
    expect(
      outcomes.where((outcome) => outcome != null),
      isNotEmpty,
      reason: 'a flapping link fails some of the time',
    );

    await fault('clear');
    expect(await probe(proxy), isNull, reason: 'the service did not come back');
  });

  test('the service that only works at home says so', () async {
    expect(await probe(proxy), isNull, reason: 'home does not answer');
    final error = await probe(away, onlyAtHome: true);
    expect(error, isNotNull, reason: 'the away address was asked anyway');
    expect(
      failureHeadline(ServiceFailureReason.onlyAtHome, subject: 'Radarr'),
      'Radarr only works at home',
    );
  });
}

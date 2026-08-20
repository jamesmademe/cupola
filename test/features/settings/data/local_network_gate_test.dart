import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The bug: on iOS the first connection to a LAN address is what raises the
/// local-network permission alert, and that connection fails while the alert is
/// still on screen. The user reads "could not reach the server", taps Allow,
/// changes nothing else, and has to work out for themselves that the test now
/// passes.
///
/// So these cases are about *ordering and attribution*, not about sockets: the
/// permission is only ever asked about after a failure it could explain, a grant
/// that arrives mid-test earns a retry, and a denial supersedes the socket's
/// verdict rather than sitting beside it.
void main() {
  /// A probe that answers [verdict] and counts how often it was consulted.
  ({LocalNetworkProbe probe, int Function() calls}) probing(
    LocalNetworkAccess verdict,
  ) {
    var calls = 0;
    return (
      probe: (String url, {Duration timeout = Duration.zero}) async {
        calls++;
        return verdict;
      },
      calls: () => calls,
    );
  }

  ServiceDiagnosis failure(ServiceFailureReason reason) =>
      ServiceDiagnosis(ServiceConnectionStatus.disconnected, reason);

  group('diagnoseThroughLocalNetworkGate', () {
    test('a denial supersedes the address the socket blamed', () async {
      final asked = probing(LocalNetworkAccess.denied);

      final result = await diagnoseThroughLocalNetworkGate(
        () async => failure(ServiceFailureReason.unreachable),
        url: 'https://192.168.1.10:7878',
        probe: asked.probe,
      );

      expect(result.reason, ServiceFailureReason.localNetworkBlocked);
      expect(asked.calls(), 1);
      // The sentence must not send the user back to the form: nothing in it is
      // wrong, and the request never left the device.
      final message = result.messageFor(ServiceKey.radarr);
      expect(message, contains('local network'));
      expect(message, isNot(contains('Check the address')));
    });

    test('a grant that lands mid-test runs the test again', () async {
      // The retest the user used to have to think of. The failed connection was
      // dialled through a gate that has since opened, so its verdict is void.
      final asked = probing(LocalNetworkAccess.justGranted);
      var attempts = 0;

      final result = await diagnoseThroughLocalNetworkGate(
        () async {
          attempts++;
          return attempts == 1
              ? failure(ServiceFailureReason.unreachable)
              : const ServiceDiagnosis.connected();
        },
        url: 'https://nas.local:8989',
        probe: asked.probe,
      );

      expect(attempts, 2);
      expect(result.isConnected, isTrue);
    });

    test(
      'a permission that was already granted does not double the wait',
      () async {
        // A wrong LAN address fails slowly. Retrying it because the permission is
        // fine would make every genuine mistake take twice as long to report.
        final asked = probing(LocalNetworkAccess.granted);
        var attempts = 0;

        final result = await diagnoseThroughLocalNetworkGate(
          () async {
            attempts++;
            return failure(ServiceFailureReason.timeout);
          },
          url: 'https://192.168.1.99:7878',
          probe: asked.probe,
        );

        expect(attempts, 1);
        expect(result.reason, ServiceFailureReason.timeout);
      },
    );

    test('an unresolved permission changes nothing', () async {
      // The alert is on screen, unanswered. Claiming either way would be a guess.
      final asked = probing(LocalNetworkAccess.unknown);

      final result = await diagnoseThroughLocalNetworkGate(
        () async => failure(ServiceFailureReason.unreachable),
        url: 'https://192.168.1.10:7878',
        probe: asked.probe,
      );

      expect(result.reason, ServiceFailureReason.unreachable);
    });

    test('a connection that worked is never asked about', () async {
      final asked = probing(LocalNetworkAccess.denied);

      final result = await diagnoseThroughLocalNetworkGate(
        () async => const ServiceDiagnosis.connected(),
        url: 'https://192.168.1.10:7878',
        probe: asked.probe,
      );

      expect(result.isConnected, isTrue);
      expect(asked.calls(), 0);
    });

    test('a failure the server itself reported is never asked about', () async {
      // Anything that reached the service proves the OS was not in the way, and
      // asking anyway is what would raise an alert nobody could make sense of.
      final asked = probing(LocalNetworkAccess.denied);

      for (final reason in [
        ServiceFailureReason.unauthorized,
        ServiceFailureReason.notFound,
        ServiceFailureReason.redirected,
        ServiceFailureReason.serverError,
        ServiceFailureReason.tls,
      ]) {
        final result = await diagnoseThroughLocalNetworkGate(
          () async => failure(reason),
          url: 'https://192.168.1.10:7878',
          probe: asked.probe,
        );
        expect(result.reason, reason, reason: '$reason was re-attributed');
      }
      expect(asked.calls(), 0);
    });
  });

  group('localNetworkCouldExplain', () {
    test('only the failures that never reached a server', () {
      expect(
        localNetworkCouldExplain(ServiceFailureReason.unreachable),
        isTrue,
      );
      expect(localNetworkCouldExplain(ServiceFailureReason.timeout), isTrue);
      expect(localNetworkCouldExplain(ServiceFailureReason.unknown), isTrue);

      // A handshake proves the packets arrived somewhere.
      expect(localNetworkCouldExplain(ServiceFailureReason.tls), isFalse);
      expect(
        localNetworkCouldExplain(ServiceFailureReason.unauthorized),
        isFalse,
      );
      // Already attributed.
      expect(
        localNetworkCouldExplain(ServiceFailureReason.localNetworkBlocked),
        isFalse,
      );
    });
  });

  group('certProbeWorthwhile', () {
    test('rules out a blocked network', () {
      // The probe opens its own socket to the same blocked address, so it can
      // only ever time out and come back null.
      expect(
        certProbeWorthwhile(ServiceFailureReason.localNetworkBlocked),
        isFalse,
      );
    });
  });

  group('connectionFailureMessage', () {
    test('names the device and the route, not the server', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final message = connectionFailureMessage(
        ServiceKey.sonarr,
        ServiceFailureReason.localNetworkBlocked,
      );

      expect(message, contains('This device is blocking Cupola'));
      expect(message, contains('Sonarr was never dialled'));
      expect(message, contains('Local Network'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

void main() {
  group('describeServerVersion', () {
    test('says nothing when the server named nothing', () {
      expect(describeServerVersion(ServiceKey.truenas, null), isNull);
      expect(describeServerVersion(ServiceKey.truenas, '   '), isNull);
    });

    test('a supported TrueNAS is reported without a caveat', () {
      final note = describeServerVersion(
        ServiceKey.truenas,
        'TrueNAS-SCALE-25.04.2',
      );

      expect(note, isNotNull);
      expect(note!.message, contains('25.04.2'));
      expect(note.isWarning, isFalse);
    });

    test('a TrueNAS below the floor is a qualified pass, not a plain one', () {
      final note = describeServerVersion(
        ServiceKey.truenas,
        'TrueNAS-SCALE-24.10.1',
      );

      // The whole point of reading the version during the test: this server
      // answers, so nothing else in the outcome can say the console is about to
      // come up half empty.
      expect(note!.isWarning, isTrue);
      expect(note.message, contains('24.10.1'));
      expect(note.message, contains(kTrueNasMinVersion));
    });

    test('an unreadable version fails open', () {
      final note = describeServerVersion(ServiceKey.truenas, 'TrueNAS-nightly');

      expect(note!.message, contains('TrueNAS-nightly'));
      expect(note.isWarning, isFalse);
    });
  });

  group('describeConnection', () {
    test('a refused redirect is not drawn as unreachable', () {
      final presentation = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.redirected,
      );

      // Red means nothing answered. Something answered — it just answered with
      // a redirect — so this is the amber "fix something" tone, and the label
      // has to say which something.
      expect(presentation.tone, StatusTone.warning);
      expect(presentation.needsAttention, isTrue);
      expect(presentation.label, isNot('Unreachable'));
      expect(presentation.label.toLowerCase(), contains('redirect'));
    });

    test('a redirect and a wrong base path do not read the same', () {
      final redirected = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.redirected,
      );
      final notFound = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.notFound,
      );

      expect(redirected.label, isNot(notFound.label));
      expect(redirected.icon, isNot(notFound.icon));
    });

    test('a blocked local network is not drawn as an unreachable server', () {
      final blocked = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.localNetworkBlocked,
      );
      final unreachable = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.unreachable,
      );

      // Red says "nothing answered", which sends the user auditing an address
      // and a port that are both fine — the request never left the device. Amber
      // says "there is one thing to change", and there is exactly one.
      expect(blocked.tone, StatusTone.warning);
      expect(unreachable.tone, StatusTone.error);
      expect(blocked.label, isNot(unreachable.label));
      expect(blocked.icon, isNot(unreachable.icon));
    });

    // The switch over `reason` is exhaustive, so this is a guard against a new
    // reason being added and quietly landing on the "Unreachable" fallback
    // rather than being given words of its own.
    test('every failure reason resolves to a state worth showing', () {
      for (final reason in ServiceFailureReason.values) {
        final presentation = describeConnection(
          ServiceKey.sonarr,
          status: ServiceConnectionStatus.disconnected,
          reason: reason,
        );
        expect(presentation.needsAttention, isTrue, reason: '$reason');
        expect(presentation.label, isNotEmpty, reason: '$reason');
      }
    });

    test('the healthy and unconfigured states stay quiet', () {
      for (final status in const [
        ServiceConnectionStatus.connected,
        ServiceConnectionStatus.notConfigured,
        ServiceConnectionStatus.checking,
      ]) {
        expect(
          describeConnection(ServiceKey.radarr, status: status).needsAttention,
          isFalse,
          reason: '$status',
        );
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

void main() {
  group('writeFailureReason', () {
    test('a refused write says it answered and that nothing changed', () {
      expect(
        writeFailureReason(
          ServiceKey.seerr,
          const ClassifiedFailure(ServiceFailureReason.unauthorized),
        ),
        'Seerr answered but refused the key. Nothing changed.',
      );
    });

    test('"did not answer" only when nothing did', () {
      expect(
        writeFailureReason(
          ServiceKey.radarr,
          const ClassifiedFailure(ServiceFailureReason.unreachable),
        ),
        'Radarr did not answer.',
      );
      expect(
        writeFailureReason(
          ServiceKey.radarr,
          const ClassifiedFailure(ServiceFailureReason.serverError),
        ),
        'Radarr answered with an error.',
      );
      for (final reason in ServiceFailureReason.values) {
        expect(
          writeFailureReason(ServiceKey.sonarr, ClassifiedFailure(reason)),
          isNot(contains('unreachable')),
          reason: reason.name,
        );
      }
    });
  });

  group('transportWarningFor', () {
    test('a TrueNAS address over http:// is refused while it is typed', () {
      expect(
        transportWarningFor(ServiceKey.truenas, 'http://nas.home.arpa'),
        const TrueNasInsecureTransportException().failureDetail,
      );
      expect(
        transportWarningFor(ServiceKey.truenas, 'ws://192.168.1.10'),
        isNotNull,
      );
      expect(
        transportWarningFor(ServiceKey.truenas, 'https://nas.home.arpa'),
        isNull,
      );
    });

    test('SABnzbd off the local network names the key in the address', () {
      expect(
        transportWarningFor(ServiceKey.sabnzbd, 'http://sab.example.net:8080'),
        contains('API key inside the address'),
      );
      // On the local network http:// is a supported setup, for SABnzbd too.
      expect(
        transportWarningFor(ServiceKey.sabnzbd, 'http://192.168.1.20:8080'),
        isNull,
      );
    });

    test('every other service leaves it to the general warning', () {
      expect(
        transportWarningFor(ServiceKey.radarr, 'http://radarr.example.net'),
        isNull,
      );
    });
  });

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

    test('red is spent only on a host that never answered', () {
      // The five-arm tone rule, applied to reachability. Amber is a fault: the
      // host replied, so there is one thing to go and fix. Red is the absence
      // of a reply, which is the only state the user cannot act on from the
      // form. A timeout is reached-then-silent and a 5xx is the service
      // talking — both used to be red, which put "your server is busy" beside
      // "no route to host". A failure nobody can attribute is amber too: it is
      // no evidence that the host is silent.
      const red = {ServiceFailureReason.unreachable};
      for (final reason in ServiceFailureReason.values) {
        final presentation = describeConnection(
          ServiceKey.radarr,
          status: ServiceConnectionStatus.disconnected,
          reason: reason,
        );
        expect(
          presentation.tone,
          red.contains(reason) ? StatusTone.error : StatusTone.warning,
          reason: '$reason',
        );
      }
    });

    test('red reads "Did not answer", and a refusal says what it refused', () {
      final silent = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.unreachable,
      );
      expect(silent.label, 'Did not answer');

      String refused(ServiceKey service) => describeConnection(
        service,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.unauthorized,
      ).label;
      expect(refused(ServiceKey.radarr), 'Refused the key');
      expect(refused(ServiceKey.plex), 'Refused the token');
      expect(refused(ServiceKey.qbittorrent), 'Refused the sign-in');
    });

    test('describeFailure names who, and the remedy the form holds', () {
      final refused = describeFailure(
        ServiceKey.radarr,
        ServiceFailureReason.unauthorized,
        subject: 'Radarr 4K',
      );
      expect(refused.headline, 'Radarr 4K answered but refused the key');
      expect(refused.remedy, 'Paste the key again');
      expect(refused.tone, StatusTone.warning);
      expect(refused.didNotAnswer, isFalse);

      final signIn = describeFailure(
        ServiceKey.qbittorrent,
        ServiceFailureReason.unauthorized,
      );
      expect(signIn.headline, 'qBittorrent answered but refused the sign-in');
      expect(signIn.remedy, 'Sign in again');

      final silent = describeFailure(
        ServiceKey.jellyfin,
        ServiceFailureReason.unreachable,
      );
      expect(silent.headline, 'Jellyfin did not answer');
      expect(silent.remedy, isNull, reason: 'Retry is the remedy');
      expect(silent.tone, StatusTone.error);
    });

    test('the failure vocabulary never says "slow"', () {
      // Three surfaces read this one function; "Slow" is explicitly outside the
      // closed vocabulary because it tells the user to wait, when what they
      // should do is look at the server.
      for (final reason in ServiceFailureReason.values) {
        final label = describeConnection(
          ServiceKey.radarr,
          status: ServiceConnectionStatus.disconnected,
          reason: reason,
        ).label;
        expect(label.toLowerCase(), isNot(contains('slow')), reason: '$reason');
      }
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

  group('the credential scope qualifier', () {
    test('a read-only answer reads in the service\'s own noun', () {
      expect(
        credentialScopeQualifier(
          ServiceKey.unraid,
          const CapabilityGrant.readOnly(),
        ),
        'read-only key',
      );
      expect(
        credentialScopeQualifier(
          ServiceKey.nginxProxyManager,
          const CapabilityGrant.readOnly(),
        ),
        'view-only account',
      );
      expect(
        credentialScopeQualifier(
          ServiceKey.truenas,
          const CapabilityGrant.refused(),
        ),
        'read-only key',
      );
      expect(
        credentialScopeQualifier(
          ServiceKey.truenas,
          const CapabilityGrant.partial({'smb'}),
        ),
        'limited key',
      );
    });

    test('nothing is claimed that nobody established', () {
      for (final grant in const [
        CapabilityGrant.unanswered(),
        CapabilityGrant.unknown(),
        CapabilityGrant.readWrite(),
      ]) {
        expect(credentialScopeQualifier(ServiceKey.unraid, grant), isNull);
      }
      expect(
        credentialScopeQualifier(
          ServiceKey.radarr,
          const CapabilityGrant.readOnly(),
        ),
        isNull,
      );
    });
  });
}

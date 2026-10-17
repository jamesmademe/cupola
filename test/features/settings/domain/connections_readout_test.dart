import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/connections_readout.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The fold behind the settings summary card: how many, in which state, and
/// what colour the whole thing is.
///
/// Every assertion here is on a rule: the tone the fold resolves, the word the
/// vocabulary supplies, never on a colour or a layout. The point of the fold
/// being pure is that these can be asked without a widget.
void main() {
  ConnectionPresentation failed(ServiceKey service, ServiceFailureReason why) =>
      describeConnection(
        service,
        status: ServiceConnectionStatus.disconnected,
        reason: why,
      );

  ConnectionPresentation answering(ServiceKey service) =>
      describeConnection(service, status: ServiceConnectionStatus.connected);

  group('the summary line', () {
    test('counts what is set up against the whole registry', () {
      final readout = ConnectionsReadout.from(
        states: {ServiceKey.radarr: answering(ServiceKey.radarr)},
        notSetUp: const [],
      );

      // The denominator is the registry, not the number of configured
      // services: "1 of 1" would call a stack with one service whole.
      expect(readout.registrySize, ServiceKey.values.length);
      expect(
        readout.summary,
        '1 of ${ServiceKey.values.length} set up\u00A0· 1 answering',
      );
    });

    test('a connection still being checked is not counted as an answer', () {
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.radarr: answering(ServiceKey.radarr),
          ServiceKey.sonarr: describeConnection(
            ServiceKey.sonarr,
            status: ServiceConnectionStatus.checking,
          ),
        },
        notSetUp: const [],
      );

      expect(readout.answering, 1);
      expect(readout.checking, 1);
      expect(readout.summary, endsWith('· 1 answering\u00A0· checking 1'));
    });
  });

  test('away from home, the ones only at home are counted apart', () {
    final readout = ConnectionsReadout.from(
      states: {
        ServiceKey.radarr: answering(ServiceKey.radarr),
        ServiceKey.sabnzbd: failed(
          ServiceKey.sabnzbd,
          ServiceFailureReason.onlyAtHome,
        ),
      },
      notSetUp: const [],
      registrySize: 17,
    );
    expect(
      readout.summary,
      '2 of 17 set up\u00A0· 1 answering\u00A0· 1 only at home',
    );
    // Never a group to fix, and the card stays green.
    expect(readout.faults, isEmpty);
    expect(readout.tone, StatusTone.success);
  });

  group('the tone of the whole card', () {
    test('a rejected key is amber, not red', () {
      // The regression this guards: the card took its tone from a boolean:
      // "anything failing at all ⇒ error", so a stack whose only complaint
      // was a wrong API key wore the colour this system reserves for nothing
      // answering, and sent the user to check cables.
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.radarr: answering(ServiceKey.radarr),
          ServiceKey.bazarr: failed(
            ServiceKey.bazarr,
            ServiceFailureReason.unauthorized,
          ),
        },
        notSetUp: const [],
      );

      expect(readout.tone, StatusTone.warning);
    });

    test('one unreachable service outranks any number of amber ones', () {
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.bazarr: failed(
            ServiceKey.bazarr,
            ServiceFailureReason.unauthorized,
          ),
          ServiceKey.sabnzbd: failed(
            ServiceKey.sabnzbd,
            ServiceFailureReason.unreachable,
          ),
        },
        notSetUp: const [],
      );

      expect(readout.tone, StatusTone.error);
    });

    test('a whole stack is green and an empty one is neutral', () {
      expect(
        ConnectionsReadout.from(
          states: {ServiceKey.radarr: answering(ServiceKey.radarr)},
          notSetUp: const [],
        ).tone,
        StatusTone.success,
      );
      // Nothing set up is not a fault: it is a fresh install.
      expect(
        ConnectionsReadout.from(
          states: const {},
          notSetUp: ServiceKey.values,
        ).tone,
        StatusTone.neutral,
      );
    });
  });

  group('failures group by state', () {
    test('two services in one state are one row that names both', () {
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.sabnzbd: failed(
            ServiceKey.sabnzbd,
            ServiceFailureReason.unreachable,
          ),
          ServiceKey.unraid: failed(
            ServiceKey.unraid,
            ServiceFailureReason.unreachable,
          ),
        },
        notSetUp: const [],
      );

      expect(readout.faults, hasLength(1));
      expect(
        readout.faults.single.names,
        '${ServiceKey.sabnzbd.title} and ${ServiceKey.unraid.title}',
      );
      // The words come from `describeConnection` and nowhere else.
      expect(
        readout.faults.single.presentation.label,
        describeConnection(
          ServiceKey.sabnzbd,
          status: ServiceConnectionStatus.disconnected,
          reason: ServiceFailureReason.unreachable,
        ).label,
      );
    });

    test('different causes stay apart, because the fixes differ', () {
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.bazarr: failed(
            ServiceKey.bazarr,
            ServiceFailureReason.unauthorized,
          ),
          ServiceKey.sabnzbd: failed(
            ServiceKey.sabnzbd,
            ServiceFailureReason.unreachable,
          ),
        },
        notSetUp: const [],
      );

      expect(readout.faults, hasLength(2));
      expect(readout.faults.map((group) => group.services.single), [
        ServiceKey.bazarr,
        ServiceKey.sabnzbd,
      ]);
    });

    test('a healthy stack has nothing to say', () {
      final readout = ConnectionsReadout.from(
        states: {
          ServiceKey.radarr: answering(ServiceKey.radarr),
          ServiceKey.sonarr: answering(ServiceKey.sonarr),
        },
        notSetUp: const [],
      );

      expect(readout.faults, isEmpty);
    });
  });

  group('joinServiceNames', () {
    test('reads as a sentence at one, two and three', () {
      expect(joinServiceNames(const []), isEmpty);
      expect(joinServiceNames([ServiceKey.radarr]), ServiceKey.radarr.title);
      expect(
        joinServiceNames([ServiceKey.radarr, ServiceKey.sonarr]),
        '${ServiceKey.radarr.title} and ${ServiceKey.sonarr.title}',
      );
      expect(
        joinServiceNames([
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
        ]),
        '${ServiceKey.radarr.title}, ${ServiceKey.sonarr.title} and '
        '${ServiceKey.lidarr.title}',
      );
    });
  });
}

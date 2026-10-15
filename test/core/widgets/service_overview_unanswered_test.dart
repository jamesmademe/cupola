/// A connection that did not answer: its Overview says so once, naming the
/// address it asked, or both when neither answered; the Home and the Stack
/// say the second of home and away.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The probe's verdict, given: these connections answered at neither address.
class _Unanswered extends UnansweredConnectionsNotifier {
  _Unanswered(this.ids);

  final Set<String> ids;

  @override
  Set<String> build() => ids;
}

const _away = ConnectionAddress(url: 'https://radarr.example.net');

void main() {
  testWidgets('the Overview says it once, naming both addresses', (
    tester,
  ) async {
    final radarr = WorldConnections.radarr.instance;
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3.withConnection(
        ProfileConnection(
          radarr.copyWith(away: _away),
          behaviour: ConnectionBehaviour.didNotAnswer,
        ),
      ),
      overrides: [
        unansweredConnectionsProvider.overrideWith(
          () => _Unanswered({radarr.id}),
        ),
      ],
      surfaceSize: const Size(430, 1600),
      child: const RadarrOverviewScreen(topPadding: 0),
    );

    final home = ServiceKey.radarr.extractHost(radarr.url);
    expect(
      find.text(
        'Radarr did not answer at home or away.\n'
        'At home · $home\n'
        'Away · radarr.example.net',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('is not shown'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('silent at the address it asked, it says that one once', (
    tester,
  ) async {
    final radarr = WorldConnections.radarr.instance;
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3.withConnection(
        ProfileConnection(
          radarr.copyWith(away: _away),
          behaviour: ConnectionBehaviour.didNotAnswer,
        ),
      ),
      surfaceSize: const Size(430, 1600),
      child: const RadarrOverviewScreen(topPadding: 0),
    );

    final home = ServiceKey.radarr.extractHost(radarr.url);
    expect(find.textContaining('at home or away'), findsNothing);
    expect(find.text('Radarr did not answer at $home.'), findsOneWidget);
    expect(find.textContaining('is not shown'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await harness.unmount(tester);
  });

  test(
    'Connections reads the connection did not answer at home or away',
    () async {
      final radarr = WorldConnections.radarr.instance;
      final harness = await ProfileHarness.start(
        Profiles.p3.withConnection(
          ProfileConnection(
            radarr.copyWith(away: _away),
            behaviour: ConnectionBehaviour.didNotAnswer,
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ...harness.overrides,
          unansweredConnectionsProvider.overrideWith(
            () => _Unanswered({radarr.id}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final diagnosis = await container.read(
        serviceDiagnosisProvider(ServiceKey.radarr).future,
      );

      expect(diagnosis.reason, ServiceFailureReason.unreachableAtBoth);
      expect(
        diagnosis.messageFor(ServiceKey.radarr),
        endsWith('Away · radarr.example.net'),
      );
    },
  );

  group('the stack', () {
    const radarr = ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://nas.home.arpa:7878',
      credential: 'key',
      away: _away,
    );
    const sonarr = ServiceInstance(
      id: 'sonarr',
      service: ServiceKey.sonarr,
      url: 'http://nas.home.arpa:8989',
      credential: 'key',
    );

    StackSilence silenceOf(List<ServiceKey> silent) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWithValue(
            const SettingsModel(instances: [radarr, sonarr]),
          ),
          unreachableServicesProvider.overrideWithValue(silent),
          unansweredConnectionsProvider.overrideWith(
            () => _Unanswered({'radarr'}),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(stackSilenceProvider);
    }

    test('nothing answered, at home or away', () {
      final silence = silenceOf([ServiceKey.radarr, ServiceKey.sonarr]);
      final needs = needsYouOf(
        silent: [ServiceKey.radarr, ServiceKey.sonarr],
        decisions: const [],
        now: DateTime(2026, 10, 15, 12, 30),
        silentAt: DateTime(2026, 10, 15, 12, 29),
        silenceScope: silence.scopeOf([ServiceKey.radarr, ServiceKey.sonarr]),
      );

      expect(needs?.line, 'No service answered, at home or away');
    });

    test('one service at both addresses, the other answering', () {
      final silence = silenceOf([ServiceKey.radarr]);

      expect(silence.scopeOf([ServiceKey.radarr]), SilenceScope.atBoth);
      expect(
        needsYouOf(
          silent: [ServiceKey.radarr],
          decisions: const [],
          now: DateTime(2026, 10, 15, 12, 30),
          silentAt: DateTime(2026, 10, 15, 12, 27),
          silenceScope: silence.scopeOf([ServiceKey.radarr]),
        )?.line,
        'Radarr did not answer at home or away',
      );
    });

    test('a service with one address is asked where it is', () {
      final silence = silenceOf([ServiceKey.sonarr]);

      expect(silence.scopeOf([ServiceKey.sonarr]), SilenceScope.asked);
    });
  });
}

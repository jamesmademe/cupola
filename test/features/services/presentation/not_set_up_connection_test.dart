/// A connection saved without its key is not asked, so it is not silent: the
/// Stack does not count it among the services that did not answer, and the
/// service is read off its other connections.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A second Radarr, saved before its key was typed.
const _keyless = ServiceInstance(
  id: 'radarr-nokey01',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'http://nas.home.arpa:7979',
);

void main() {
  test('it reads as not set up, and Radarr as its other connection', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(ProfileConnection(_keyless)),
    );
    final container = harness.container(retry: (_, _) => null);

    final keyless = await container.read(
      instanceSummaryProvider((
        service: ServiceKey.radarr,
        instanceId: _keyless.id,
      )).future,
    );
    expect(keyless.status, ServiceSummaryStatus.notSetUp);
    expect(keyless.didNotAnswer, isFalse);
    expect(keyless.isFault, isFalse);

    // The household's two Radarr, which answer.
    for (final id in container.read(
      serviceInstanceIdsProvider(ServiceKey.radarr),
    )) {
      await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: id,
        )).future,
      );
    }
    final radarr = container.read(
      foldedServiceHealthProvider(ServiceKey.radarr),
    );
    expect(radarr.total, 2, reason: 'the two set up, not the keyless one');
    expect(radarr.offline, 0);
    expect(
      foldServiceState(
        total: radarr.total,
        offline: radarr.offline,
        faulted: radarr.faulted,
        stuck: radarr.stuck,
        checking: radarr.checking,
        onlyAtHome: radarr.onlyAtHome,
      ),
      StackServiceState.answering,
    );
  });
}

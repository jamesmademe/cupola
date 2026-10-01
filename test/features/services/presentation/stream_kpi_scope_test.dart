/// A media server's figures say what its token cannot read, and only that.
///
/// A shared account's Plex token is refused who is watching, and a household
/// member's Jellyfin token the library list. Either refusal took the whole
/// rail into one "Refused the key" card, beside a Now playing that says, in
/// blue, why nothing is shown: the token was fine. The figure the token
/// cannot read now reads `—` with the reason, and the others still count.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<Map<String, ServiceKpi>> _figures(
  ProfileHarness harness,
  ServiceKey service, {
  String? instanceId,
}) async {
  final container = harness.container(retry: (_, _) => null);
  final List<ServiceKpi>? kpis = instanceId == null
      ? await container.read(serviceKpiProvider(service).future)
      : await container.read(
          serviceKpiForProvider((
            service: service,
            instanceId: instanceId,
          )).future,
        );
  return {for (final kpi in kpis!) kpi.label: kpi};
}

void main() {
  test('P6, a shared account\'s Plex: who is watching reads "—", owner '
      'only, and the libraries still count', () async {
    final harness = await ProfileHarness.start(Profiles.p6);
    final figures = await _figures(harness, ServiceKey.plex);

    expect(figures['Streams']!.value, ServiceKpi.unavailableValue);
    expect(figures['Streams']!.note, 'owner only');
    expect(figures['Transcodes']!.value, ServiceKpi.unavailableValue);
    // The world's Plex has four library sections.
    expect(figures['Libraries']!.value, '4');
  });

  test('the owner\'s Plex token counts every figure', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.plex),
    );
    final figures = await _figures(harness, ServiceKey.plex);

    expect(figures['Streams']!.value, '0');
    expect(figures['Transcodes']!.value, '0');
    expect(figures['Libraries']!.value, '4');
  });

  test('a token Plex refuses everywhere still takes the rail', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(
        WorldConnections.plex.withBehaviour(ConnectionBehaviour.refusesKey),
      ),
    );

    await expectLater(_figures(harness, ServiceKey.plex), throwsA(anything));
  });

  test('P2+J, a household member\'s Jellyfin: the libraries read "—", admin '
      'only, and her own playback counts', () async {
    final harness = await ProfileHarness.start(Profiles.p2WithJellyfin);
    final figures = await _figures(harness, ServiceKey.jellyfin);

    expect(figures['Libraries']!.value, ServiceKpi.unavailableValue);
    expect(figures['Libraries']!.note, 'admin only');
    // Anna watching Sintel on the living room TV.
    expect(figures['Streams']!.value, '1');
    expect(figures['Transcodes']!.value, '0');
  });

  test('the cabin\'s Jellyfin on a member\'s token, read on its own: the '
      'same, while the API key at home counts its libraries', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(
        WorldConnections.jellyfinCabin.withBehaviour(
          ConnectionBehaviour.readOnly,
        ),
      ),
    );

    final cabin = await _figures(
      harness,
      ServiceKey.jellyfin,
      instanceId: WorldIds.jellyfinCabin,
    );
    expect(cabin['Libraries']!.value, ServiceKpi.unavailableValue);
    expect(cabin['Libraries']!.note, 'admin only');
    expect(cabin['Streams']!.value, '1');

    final home = await _figures(harness, ServiceKey.jellyfin);
    expect(home['Libraries']!.value, '4');
  });
}

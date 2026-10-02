/// The `×2` card's figures on P1, where the HD and the 4K Radarr hold three
/// of the same films.
///
/// The card used to add the two film counts, 6 and 4, and print "10 movies"
/// for a household with 7 films. A count of titles is a count of distinct
/// titles; the missing copies are files to fetch on each server, and add up.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  test('P1: Radarr ×2 counts seven films, and four missing copies', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);
    final sub = container.listen(
      foldedServiceKpisProvider(ServiceKey.radarr),
      (_, _) {},
    );
    addTearDown(sub.close);

    final folded = await container.read(
      foldedServiceKpisProvider(ServiceKey.radarr).future,
    );

    String figure(String label) =>
        folded!.firstWhere((kpi) => kpi.label == label).value;
    // Sprite Fright, Big Buck Bunny, Coffee Run, Sintel, Tears of Steel,
    // Elephants Dream and Spring: Sintel, Tears of Steel and Elephants Dream
    // are on both.
    expect(figure('Movies'), '7');
    expect(figure('Monitored'), '7');
    // Two on the HD (Sprite Fright, Big Buck Bunny), two on the 4K
    // (Elephants Dream, Sintel).
    expect(figure('Missing'), '4');
  });

  Future<List<ServiceKpi>?> folded(
    ProfileHarness harness,
    ServiceKey service,
  ) async {
    final container = harness.container(retry: (_, _) => null);
    final sub = container.listen(foldedServiceKpisProvider(service), (_, _) {});
    addTearDown(sub.close);
    return container.read(foldedServiceKpisProvider(service).future);
  }

  test(
    'P1 + the vinyl Lidarr: Lidarr ×2 counts the albums both hold once',
    () async {
      // Both Lidarr hold Jan Morgenstern's four albums. Off the artists, which
      // name no album, the card added 4 and 4.
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(WorldConnections.lidarrVinyl),
      );
      final kpis = await folded(harness, ServiceKey.lidarr);

      String figure(String label) =>
          kpis!.firstWhere((kpi) => kpi.label == label).value;
      expect(figure('Albums'), '4');
      expect(figure('Artists'), '1');
      // And the albums were asked of both, library-wide.
      bool library(NetworkRequest r) =>
          r.uri.path == '/api/v1/album' &&
          !r.uri.queryParameters.containsKey('artistId');
      expect(
        harness.network.requestsTo(WorldIds.lidarr).where(library),
        isNotEmpty,
      );
      expect(
        harness.network.requestsTo(WorldIds.lidarrVinyl).where(library),
        isNotEmpty,
      );
    },
  );

  test('the vinyl Lidarr\'s albums unreadable: the album figure is a dash, '
      'never a sum standing in for the union', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.lidarrVinyl),
    );
    harness.network.on(
      WorldIds.lidarrVinyl,
      'GET',
      '/api/v1/album',
      (r) => r.uri.queryParameters.containsKey('artistId')
          ? null
          : NetworkReply.json({'message': 'boom'}, status: 500),
    );
    final kpis = await folded(harness, ServiceKey.lidarr);

    expect(
      kpis!.firstWhere((kpi) => kpi.label == 'Albums').isUnavailable,
      isTrue,
    );
  });

  test('P1 + the cabin Jellyfin: the ×2 card shows sessions, which belong to '
      'one server each, and never the library sections', () async {
    // A session plays on one server, so two servers' sessions add up. Their
    // library sections may list the same folders, so their sum is not a count
    // of anything the household holds once; it never reaches the card.
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.jellyfinCabin),
    );
    final container = harness.container(retry: (_, _) => null);
    final sub = container.listen(
      foldedServiceSignalPairProvider(ServiceKey.jellyfin),
      (_, _) {},
    );
    addTearDown(sub.close);

    final pair = await container.read(
      foldedServiceSignalPairProvider(ServiceKey.jellyfin).future,
    );
    expect(pair, isNotNull);
    final labels = [pair!.primary.label, ?pair.secondary?.label];
    expect(labels.any((label) => label.contains('librar')), isFalse);
    // Anna on each server: two streams.
    expect(pair.primary.value, '2');
  });

  test('P1 + the cabin Jellyfin on a member\'s token: the ×2 card counts '
      'at least two streams, never two', () async {
    // The cabin's token sees only its own member's playback, so its count is
    // part of that server's. The sum used to read "2", the figure of a whole
    // household, and dropped the note that said one term was hers alone.
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(
        WorldConnections.jellyfinCabin.withBehaviour(
          ConnectionBehaviour.readOnly,
        ),
      ),
    );
    final container = harness.container(retry: (_, _) => null);
    final sub = container.listen(
      foldedServiceSignalPairProvider(ServiceKey.jellyfin),
      (_, _) {},
    );
    addTearDown(sub.close);

    final pair = await container.read(
      foldedServiceSignalPairProvider(ServiceKey.jellyfin).future,
    );

    expect(pair!.primary.value, '2+');
    expect(pair.primary.spoken, 'Streaming at least 2');
  });
}

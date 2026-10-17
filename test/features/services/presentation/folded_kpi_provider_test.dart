/// The fleet's figures, and the three ways the app refuses to invent them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_sync.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

/// The lens, because `activeInstanceProvider` falls back to the first instance.
const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'k',
);

/// Two qBittorrent connections, used to verify that a named KPI reader does
/// not silently fall back to the active lens.
const _qbLens = ServiceInstance(
  id: 'qbittorrent',
  service: ServiceKey.qbittorrent,
  label: 'Seedbox',
  url: 'https://seedbox.lan:8080',
  credential: 'k',
  username: 'u',
);
const _qbOther = ServiceInstance(
  id: 'qbittorrent-22222',
  service: ServiceKey.qbittorrent,
  label: 'Home',
  url: 'https://home.lan:8080',
  credential: 'k',
  username: 'u',
);

class _Movies extends FakeRadarrService {
  _Movies(this.movies);

  final List<RadarrMovie> movies;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;
}

class _Torrents extends QbittorrentService {
  _Torrents(this.torrents) : super(QbittorrentClient(url: 'https://qbit.test'));

  final List<Torrent> torrents;

  @override
  Future<QbittorrentMainData> mainData() async => QbittorrentMainData(
    torrents: torrents,
    transfer: TransferInfo.fromJson(const {}),
  );
}

ServiceSummary _summary(ServiceKey service, {required bool online}) =>
    ServiceSummary(
      service: service,
      status: online
          ? ServiceSummaryStatus.online
          : ServiceSummaryStatus.offline,
      host: 'somewhere',
      version: online ? '5.0' : null,
    );

ProviderContainer _container({
  List<ServiceInstance> instances = const [_fourK, _hd],
  Set<String> dark = const {},
  List<RadarrMovie> lensMovies = const [],
  List<RadarrMovie> otherMovies = const [],
  QbittorrentService? qbittorrentService,
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => SettingsModel(instances: instances),
      ),
      instanceSummaryProvider.overrideWith(
        (ref, key) async =>
            _summary(key.service, online: !dark.contains(key.instanceId)),
      ),
      // The lens leg reads the provider the library screen reads, so a folded
      // card and the list behind it cannot disagree about the same server.
      radarrServiceProvider.overrideWith((ref) => _Movies(lensMovies)),
      // The named leg builds its own client from the id. This family is the
      // whole reason Radarr can answer per connection at all.
      radarrServiceForProvider.overrideWith((ref, id) => _Movies(otherMovies)),
      if (qbittorrentService != null)
        qbittorrentServiceForProvider.overrideWith(
          (ref, id) => qbittorrentService,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('foldedServiceKpisProvider', () {
    test(
      'a count of distinct films is the films of every connection',
      () async {
        final container = _container(
          lensMovies: [
            buildMovie(id: 1, tmdbId: 101),
            buildMovie(id: 2, tmdbId: 102),
          ],
          otherMovies: [
            buildMovie(id: 3, tmdbId: 103),
            buildMovie(id: 4, tmdbId: 104),
            buildMovie(id: 5, tmdbId: 105),
          ],
        );

        final folded = await container.read(
          foldedServiceKpisProvider(ServiceKey.radarr).future,
        );

        expect(folded, isNotNull);
        final movies = folded!.firstWhere((kpi) => kpi.label == 'Movies');
        expect(movies.value, '5');
      },
    );

    test('a film both libraries hold is one film, and its missing copies '
        'are two files to fetch', () async {
      // HD and 4K: the same two films in each, neither copy on disk. Added up
      // as counts, the card read "4 movies" for two films.
      final container = _container(
        lensMovies: [
          buildMovie(id: 1, tmdbId: 101, hasFile: false),
          buildMovie(id: 2, tmdbId: 102, hasFile: false),
        ],
        otherMovies: [
          buildMovie(id: 1, tmdbId: 102, hasFile: false),
          buildMovie(id: 2, tmdbId: 101, hasFile: false),
        ],
      );

      final folded = await container.read(
        foldedServiceKpisProvider(ServiceKey.radarr).future,
      );

      String figure(String label) =>
          folded!.firstWhere((kpi) => kpi.label == label).value;
      expect(figure('Movies'), '2');
      expect(figure('Monitored'), '2');
      expect(figure('Missing'), '4');
    });

    test('a dark connection shows no figure at all', () async {
      // Not "the lens's figures with a ×2 beside them", and not a sum over the
      // servers that did answer: a sum missing a term looks exactly like a sum.
      final container = _container(
        dark: const {'radarr-hd11111'},
        lensMovies: [buildMovie(id: 1), buildMovie(id: 2)],
        otherMovies: [buildMovie(id: 3)],
      );

      expect(
        await container.read(
          foldedServiceKpisProvider(ServiceKey.radarr).future,
        ),
        isNull,
      );
    });

    test('one connection folds to its own figures', () async {
      final container = _container(
        instances: const [_fourK],
        lensMovies: [buildMovie(id: 1), buildMovie(id: 2)],
      );

      final folded = await container.read(
        foldedServiceKpisProvider(ServiceKey.radarr).future,
      );

      expect(folded!.firstWhere((kpi) => kpi.label == 'Movies').value, '2');
    });
  });

  group('serviceKpiForProvider', () {
    test('the lens collapses onto the plain provider', () async {
      final container = _container(
        lensMovies: [buildMovie(id: 1)],
        otherMovies: [buildMovie(id: 2), buildMovie(id: 3)],
      );

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.radarr,
          instanceId: _fourK.id,
        )).future,
      );

      expect(kpis!.firstWhere((kpi) => kpi.label == 'Movies').value, '1');
    });

    test('a named connection reads that connection, not the lens', () async {
      final container = _container(
        lensMovies: [buildMovie(id: 1)],
        otherMovies: [buildMovie(id: 2), buildMovie(id: 3)],
      );

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.radarr,
          instanceId: _hd.id,
        )).future,
      );

      expect(kpis!.firstWhere((kpi) => kpi.label == 'Movies').value, '2');
    });

    test('a named qBittorrent connection does not read the lens', () async {
      final container = _container(
        instances: const [_qbLens, _qbOther],
        qbittorrentService: _Torrents([
          Torrent.fromJson({'state': 'downloading', 'dlspeed': 128}),
        ]),
      );

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.qbittorrent,
          instanceId: _qbOther.id,
        )).future,
      );

      expect(kpis, isNotNull);
      expect(kpis!.firstWhere((kpi) => kpi.label == 'Active').value, '1');
    });

    test('a stuck or failed torrent is counted on the card and flagged, by '
        'the rule Needs you uses', () async {
      final container = _container(
        instances: const [_qbLens, _qbOther],
        qbittorrentService: _Torrents([
          Torrent.fromJson({'state': 'downloading', 'dlspeed': 128}),
          Torrent.fromJson({'state': 'stalledDL'}),
          Torrent.fromJson({'state': 'error'}),
        ]),
      );

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.qbittorrent,
          instanceId: _qbOther.id,
        )).future,
      );

      final stuck = kpis!.firstWhere(
        (kpi) => kpi.label == StateWord.stuck.label,
      );
      expect(stuck.value, '2');
      expect(stuck.tone, StatusTone.warning);
    });
  });
}

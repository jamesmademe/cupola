import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';

/// Lens connections. Every fixture here adds against the OTHER one, so a
/// dispatch that quietly fell back to the lens would reach these fakes and be
/// caught.
const _sonarrLens = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  label: 'Home',
  url: 'http://home.lan:8989',
  credential: 'k',
);
const _sonarrAway = ServiceInstance(
  id: 'sonarr-away111',
  service: ServiceKey.sonarr,
  label: 'Away',
  url: 'http://away.lan:8989',
  credential: 'k',
);
const _lidarrLens = ServiceInstance(
  id: 'lidarr',
  service: ServiceKey.lidarr,
  label: 'Home',
  url: 'http://home.lan:8686',
  credential: 'k',
);
const _lidarrAway = ServiceInstance(
  id: 'lidarr-away111',
  service: ServiceKey.lidarr,
  label: 'Away',
  url: 'http://away.lan:8686',
  credential: 'k',
);

void main() {
  test('a series add reaches the section, not the lens', () async {
    final lens = _FakeSonarr(profileId: 1, rootFolder: '/home/tv');
    final away = _FakeSonarr(profileId: 9, rootFolder: '/away/tv');
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_sonarrLens, _sonarrAway]),
        ),
        sonarrServiceProvider.overrideWith((ref) => lens),
        sonarrServiceForProvider(_sonarrAway.id).overrideWithValue(away),
      ],
    );
    addTearDown(container.dispose);

    const args = (instanceId: 'sonarr-away111', service: ServiceKey.sonarr);
    // A live listener, because the form is autoDispose: without one the
    // container tears it down before its deferred load can write anything.
    final sub = container.listen(arrAddFormProvider(args), (_, _) {});
    addTearDown(sub.close);
    final notifier = container.read(arrAddFormProvider(args).notifier);
    await _settle();

    // Defaults came from the section's own server.
    expect(container.read(arrAddFormProvider(args)).profileId, 9);
    expect(container.read(arrAddFormProvider(args)).rootFolder, '/away/tv');

    final error = await notifier.submit(
      const SonarrAddRequest(
        instanceId: 'sonarr-away111',
        series: SonarrSeries(
          id: 0,
          title: 'Severance',
          sortTitle: 'severance',
          titleSlug: 'severance',
          status: 'continuing',
          monitored: false,
          year: 2022,
          images: [],
          tvdbId: 371980,
          runtime: 50,
          genres: [],
          seasons: [],
        ),
      ),
    );

    expect(error, isNull);
    expect(away.added, hasLength(1));
    expect(away.added.single.qualityProfileId, 9);
    expect(lens.added, isEmpty);
  });

  test(
    'an artist add carries the metadata profile Lidarr insists on',
    () async {
      final lens = _FakeLidarr();
      final away = _FakeLidarr(metadataProfileId: 7);
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: [_lidarrLens, _lidarrAway]),
          ),
          lidarrServiceProvider.overrideWith((ref) => lens),
          lidarrServiceForProvider(_lidarrAway.id).overrideWithValue(away),
        ],
      );
      addTearDown(container.dispose);

      const args = (instanceId: 'lidarr-away111', service: ServiceKey.lidarr);
      final sub = container.listen(arrAddFormProvider(args), (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(arrAddFormProvider(args).notifier);
      await _settle();

      expect(
        container.read(arrAddFormProvider(args)).metadataProfiles,
        isNotEmpty,
      );

      final error = await notifier.submit(
        const LidarrAddRequest(
          instanceId: 'lidarr-away111',
          artist: LidarrArtist(
            id: 0,
            artistName: 'Boards of Canada',
            foreignArtistId: 'mbid-1',
            status: 'active',
            monitored: false,
            images: [],
            genres: [],
          ),
        ),
      );

      expect(error, isNull);
      expect(away.added.single.metadataProfileId, 7);
      expect(lens.added, isEmpty);
    },
  );

  test('a Lidarr with no metadata profile cannot be added to', () async {
    // Not a form the user can submit and not a silent failure at post time:
    // Lidarr rejects an add without one, so the sheet says so up front.
    final away = _FakeLidarr(metadataProfiles: const []);
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_lidarrLens, _lidarrAway]),
        ),
        lidarrServiceProvider.overrideWith((ref) => _FakeLidarr()),
        lidarrServiceForProvider(_lidarrAway.id).overrideWithValue(away),
      ],
    );
    addTearDown(container.dispose);

    const args = (instanceId: 'lidarr-away111', service: ServiceKey.lidarr);
    final sub = container.listen(arrAddFormProvider(args), (_, _) {});
    addTearDown(sub.close);
    await _settle();

    final state = container.read(arrAddFormProvider(args));
    expect(state.error, 'Lidarr · Away has no metadata profile configured.');
    expect(state.canSubmit, isFalse);
  });

  test('a completed add is remembered under its connection', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const request = RadarrAddRequest(
      instanceId: 'radarr-away111',
      movie: _dune,
    );
    container
        .read(libraryAdditionsProvider.notifier)
        .markAdded(request.libraryKey);

    expect(
      container.read(libraryAdditionsProvider),
      contains('radarr-away111:radarr:438631'),
    );
    // The same film on the OTHER Radarr is a different claim, and both rows are
    // on screen at once.
    expect(
      container.read(libraryAdditionsProvider),
      isNot(contains('radarr:radarr:438631')),
    );
  });
}

const _dune = RadarrMovie(
  id: 0,
  title: 'Dune',
  sortTitle: 'dune',
  sizeOnDisk: 0,
  status: 'released',
  hasFile: false,
  monitored: false,
  year: 2021,
  images: [],
  tmdbId: 438631,
  runtime: 155,
  genres: [],
);

/// Lets the notifier's deferred load run to completion.
///
/// Several turns, not one: the load is a `Future.microtask` that then awaits a
/// record of futures, so a single yield leaves it half done.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _SonarrAdd {
  final int qualityProfileId;
  final String rootFolderPath;

  _SonarrAdd(this.qualityProfileId, this.rootFolderPath);
}

class _FakeSonarr extends FakeSonarrService {
  final int profileId;
  final String rootFolder;
  final List<_SonarrAdd> added = [];

  _FakeSonarr({required this.profileId, required this.rootFolder});

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': profileId, 'name': 'Any'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getRootFolders() async => [
    {'id': 1, 'path': rootFolder},
  ];

  @override
  Future<SonarrSeries> addSeries(
    SonarrSeries series, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMissingEpisodes = true,
  }) async {
    added.add(_SonarrAdd(qualityProfileId, rootFolderPath));
    return series;
  }
}

class _LidarrAdd {
  final int metadataProfileId;

  _LidarrAdd(this.metadataProfileId);
}

class _FakeLidarr extends FakeLidarrService {
  final int metadataProfileId;
  final List<Map<String, dynamic>>? metadataProfiles;
  final List<_LidarrAdd> added = [];

  _FakeLidarr({this.metadataProfileId = 1, this.metadataProfiles});

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': 2, 'name': 'Any'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getRootFolders() async => [
    {'id': 1, 'path': '/music'},
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchMetadataProfiles() async =>
      metadataProfiles ??
      [
        {'id': metadataProfileId, 'name': 'Standard'},
      ];

  @override
  Future<LidarrArtist> addArtist(
    LidarrArtist artist, {
    required int qualityProfileId,
    required int metadataProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMissingAlbums = true,
  }) async {
    added.add(_LidarrAdd(metadataProfileId));
    return artist;
  }
}

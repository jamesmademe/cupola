import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/series/domain/sonarr_monitor.dart';
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

/// A service with no add form at all, for the arm that used to be a `default:`.
const _bazarr = ServiceInstance(
  id: 'bazarr',
  service: ServiceKey.bazarr,
  label: 'Away',
  url: 'http://away.lan:6767',
  credential: 'k',
);

const _severance = SonarrAddRequest(
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

  test('the next row on the same section can still be added', () async {
    // This entry is keyed on the CONNECTION, not on the item, and outlives the
    // sheet by however long autoDispose takes. Adding one row and immediately
    // opening the next one in the same section therefore reuses this state, so
    // a submit that leaves `isSubmitting` set hands the second sheet a dead Add
    // button with nothing on screen to explain it.
    final away = _FakeSonarr(profileId: 9, rootFolder: '/away/tv');
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_sonarrLens, _sonarrAway]),
        ),
        sonarrServiceProvider.overrideWith(
          (ref) => _FakeSonarr(profileId: 1, rootFolder: '/home/tv'),
        ),
        sonarrServiceForProvider(_sonarrAway.id).overrideWithValue(away),
      ],
    );
    addTearDown(container.dispose);

    const args = (instanceId: 'sonarr-away111', service: ServiceKey.sonarr);
    final sub = container.listen(arrAddFormProvider(args), (_, _) {});
    addTearDown(sub.close);
    final notifier = container.read(arrAddFormProvider(args).notifier);
    await _settle();
    expect(container.read(arrAddFormProvider(args)).canSubmit, isTrue);

    expect(await notifier.submit(_severance), isNull);

    final state = container.read(arrAddFormProvider(args));
    expect(state.isSubmitting, isFalse);
    expect(state.canSubmit, isTrue);
  });

  test(
    'a service with no add form is refused, not treated as another arr',
    () async {
      // `ArrAddRequest` is sealed so that an arr added later is a compile error
      // rather than a plus over a sheet that cannot post. A `default:` arm here
      // handed that guarantee straight back: it fetched one arr's profiles for
      // whatever key arrived, and the sheet came up looking perfectly fillable.
      // The Sonarr fake below is wired to the Bazarr id precisely so the defect
      // would find it.
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: [_sonarrLens, _bazarr]),
          ),
          sonarrServiceProvider.overrideWith(
            (ref) => _FakeSonarr(profileId: 1, rootFolder: '/home/tv'),
          ),
          sonarrServiceForProvider(_bazarr.id).overrideWithValue(
            _FakeSonarr(profileId: 9, rootFolder: '/away/tv'),
          ),
        ],
      );
      addTearDown(container.dispose);

      const args = (instanceId: 'bazarr', service: ServiceKey.bazarr);
      final sub = container.listen(arrAddFormProvider(args), (_, _) {});
      addTearDown(sub.close);
      await _settle();

      final state = container.read(arrAddFormProvider(args));
      expect(state.isLoading, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.profiles, isEmpty);
      // "Bazarr", not "Bazarr · Away": there is one Bazarr in this model, and a
      // connection is named only when there is a second to tell it apart from.
      // The label on the fixture is left over from a sibling this test does not
      // configure: exactly the state `SettingsModel.connectionTitle` exists to
      // read past, since a real one is left behind by removing that sibling.
      // Nothing was sent, and nothing claims a server went silent: an error
      // nobody can attribute is amber, in the classified words.
      expect(state.error, 'The request to Bazarr did not complete.');
      expect(state.errorDetail, 'The request did not complete.');
      expect(state.errorReason, ServiceFailureReason.unknown);
    },
  );

  test('a submit with nothing chosen refuses out loud', () async {
    // null is this method's word for "it is on the server now": a caller that
    // gets it back closes the sheet and marks the row added. Refusing to post
    // and reporting success is the exact lie the method exists to prevent.
    final away = _FakeSonarr(
      profileId: 9,
      rootFolder: '/away/tv',
      // A server with nothing set up: the form loads, but there is nothing
      // honest to post, so no default is chosen.
      qualityProfiles: const [],
    );
    final lens = _FakeSonarr(profileId: 1, rootFolder: '/home/tv');
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
    final sub = container.listen(arrAddFormProvider(args), (_, _) {});
    addTearDown(sub.close);
    final notifier = container.read(arrAddFormProvider(args).notifier);
    await _settle();
    expect(container.read(arrAddFormProvider(args)).profileId, isNull);

    final error = await notifier.submit(_severance);

    expect(error, "Could not add Severance to Sonarr\u00A0· Away.");
    final state = container.read(arrAddFormProvider(args));
    // A refusal, in words, not an exception caught by the handler that exists
    // for a server saying no, and nothing was posted to either connection.
    expect(state.errorDetail, 'the form is not filled in');
    expect(state.isSubmitting, isFalse);
    expect(away.added, isEmpty);
    expect(lens.added, isEmpty);
  });
}

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

  /// Overrides the single generated profile, for the fixture that needs a
  /// server with none.
  final List<Map<String, dynamic>>? qualityProfiles;
  final List<_SonarrAdd> added = [];

  _FakeSonarr({
    required this.profileId,
    required this.rootFolder,
    this.qualityProfiles,
  });

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async =>
      qualityProfiles ??
      [
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
    SonarrMonitor monitor = SonarrMonitor.all,
    String? seriesType,
  }) async {
    added.add(_SonarrAdd(qualityProfileId, rootFolderPath));
    return series;
  }
}

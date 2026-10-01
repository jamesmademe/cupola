/// A library grid keys itself on the connection it shows.
///
/// The Movies, Series and Music grids show the lens's library and build every
/// poster off an address and a key. They took both from the first connection,
/// so with the lens on the 4K Radarr the grid drew its movies' artwork from
/// the HD server, under the HD's ids, and editing the 4K's address did not
/// re-key the grid while editing the HD's did.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_browse_scaffold.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/profiles/profiles.dart';

SettingsModel _moved(SettingsModel settings, String id, String url) =>
    settings.copyWithInstance(settings.instanceById(id)!.copyWith(url: url));

void main() {
  testWidgets('P1, lens on the 4K: the Movies grid keys on the 4K, and only '
      'an edit to the 4K re-keys it', (tester) async {
    final profile = Profiles.p1.withLens(ServiceKey.radarr, WorldIds.radarr4k);
    final harness = await pumpWithProfile(
      tester,
      profile,
      child: const MoviesScreen(),
    );
    final select = tester
        .widget<MediaBrowseScaffold<RadarrMovie>>(
          find.byType(MediaBrowseScaffold<RadarrMovie>),
        )
        .settingsSelector;
    final settings = profile.settings;

    expect(select(settings), (
      WorldHosts.radarr4k,
      worldKey(WorldIds.radarr4k),
    ));
    // The HD moved: the grid it does not show stays keyed as it was.
    expect(
      select(_moved(settings, WorldIds.radarr, 'http://tower.home.arpa:7878')),
      select(settings),
    );
    // The 4K moved: the grid re-keys onto its new address.
    expect(
      select(
        _moved(settings, WorldIds.radarr4k, 'https://tower.home.arpa:7879'),
      ).$1,
      'https://tower.home.arpa:7879',
    );

    await harness.unmount(tester);
  });

  testWidgets('P1, lens on the HD: the grid keys on the HD', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const MoviesScreen(),
    );
    final select = tester
        .widget<MediaBrowseScaffold<RadarrMovie>>(
          find.byType(MediaBrowseScaffold<RadarrMovie>),
        )
        .settingsSelector;

    expect(select(Profiles.p1.settings), (
      WorldHosts.radarr,
      worldKey(WorldIds.radarr),
    ));

    await harness.unmount(tester);
  });

  testWidgets('P6, lens on the anime Sonarr: the Series grid keys on it', (
    tester,
  ) async {
    final profile = Profiles.p6.withLens(
      ServiceKey.sonarr,
      WorldIds.sonarrAnime,
    );
    final harness = await pumpWithProfile(
      tester,
      profile,
      child: const SeriesScreen(),
    );
    final select = tester
        .widget<MediaBrowseScaffold<SonarrSeries>>(
          find.byType(MediaBrowseScaffold<SonarrSeries>),
        )
        .settingsSelector;

    expect(select(profile.settings), (
      WorldHosts.sonarrAnime,
      worldKey(WorldIds.sonarrAnime),
    ));

    await harness.unmount(tester);
  });
}

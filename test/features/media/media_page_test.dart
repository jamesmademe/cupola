/// The canonical Media page against the households: who the title is, the
/// one lead, and every row spoken as one sentence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/core/widgets/machine_name.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await pumpWithProfile(
    tester,
    profile,
    overrides: overrides,
    child: MediaPage(mediaKey: MediaKey.movie(title.tmdbId)),
    settle: false,
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return harness;
}

/// The page under a router, for the rows that lead somewhere: anything
/// under Settings draws its own location.
Future<(ProfileHarness, GoRouter)> _pumpRouted(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title,
) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            MediaPage(mediaKey: MediaKey.movie(title.tmdbId)),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) => Text('at ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router);
}

/// Lets the profile's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('P1, Tears of Steel: its title, Play on Jellyfin, its rows', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.text('Play on Jellyfin'), findsOneWidget);
    // The marks: Jellyfin's copy is 2160p in HDR10.
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HDR10'), findsOneWidget);
    expect(find.text('On your server'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Available$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Bazarr\. DE wanted$')),
      findsOneWidget,
    );
    expect(find.text('Manage'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('the collection says how much of it is on the server', (
    tester,
  ) async {
    final (harness, router) = await _pumpRouted(
      tester,
      Profiles.p1,
      WorldTitles.tearsOfSteel,
    );

    final band = find.bySemanticsLabel(
      'Blender Open Movies, 5 of 8 on your server',
    );
    await tester.ensureVisible(band);
    expect(band, findsOneWidget);
    expect(find.text('Collection'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('Files & quality opens on each copy\'s file, read only then', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.byType(FileInfoSection), findsNothing);
    await tester.tap(find.text('Files & quality'));
    await tester.pump();

    expect(find.byType(FileInfoSection), findsNWidgets(2));

    await harness.unmount(tester);
  });

  testWidgets('History opens on each copy\'s own imports', (tester) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('History'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 1080p Bluray\. ')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 2160p Bluray\. ')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P4, without Seerr: one dimmed row that sets it up', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    expect(find.text('Set up Seerr'), findsOneWidget);
    // Watchlist is Seerr's: without one it steps aside, no dimmed copy.
    expect(find.text('Watchlist'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P7, Jellyfin silent: no Play, and its row offers Retry', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    expect(find.textContaining('Play on'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Did not answer.*Retry$')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('a row not set up is the way to its form, pill and all', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p4,
      WorldTitles.tearsOfSteel,
    );

    await tester.tap(find.text('Set up Seerr'));
    await tester.pumpAndSettle();
    expect(
      find.text('at ${ServiceRoutes.setUp(ServiceKey.seerr)}'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Retry asks the silent connection again, and only it', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p7,
      WorldTitles.tearsOfSteel,
    );
    // By address and port: the household's services share a host.
    String at(ServiceKey service) => Uri.parse(
      harness.profile.settings.instancesOf(service).first.url,
    ).authority;
    int asked(ServiceKey service) => harness.network.requests
        .where((request) => request.uri.authority == at(service))
        .length;
    final jellyfin = asked(ServiceKey.jellyfin);
    final radarr = asked(ServiceKey.radarr);
    final bazarr = asked(ServiceKey.bazarr);
    expect(jellyfin, greaterThan(0));

    // Bazarr is silent too, and keeps its own Retry.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Retry$')));
    await _answer(tester);

    expect(asked(ServiceKey.jellyfin), greaterThan(jellyfin));
    expect(asked(ServiceKey.radarr), radarr);
    expect(asked(ServiceKey.bazarr), bazarr);

    await harness.unmount(tester);
  });

  testWidgets('Subtitles opens on what Bazarr has and still wants', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Subtitles'));
    await tester.pump();
    expect(find.text('Wanted'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Add opens on the Radarr, its profile, folder and indexers', (
    tester,
  ) async {
    // P1 holds no Metropolis: the first Radarr leads, and the sheet says
    // what adding it there means.
    final harness = await _pump(tester, Profiles.p1, WorldTitles.metropolis);
    final lead = find.widgetWithText(FilledButton, 'Add to Radarr');
    expect(lead, findsOneWidget);

    await tester.tap(lead);
    await _answer(tester);
    expect(find.text('Metropolis · 1927'), findsOneWidget);
    expect(find.text('Instance'), findsOneWidget);
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('/mnt/tank/media/films'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^11\.3.TB free$')), findsOneWidget);
    expect(find.text('Grabs it and upgrades it to HD-1080p'), findsOneWidget);
    expect(find.text('Asks your 2 indexers right away'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add and search'), findsOneWidget);

    // Unmonitored, Radarr never looks: the search goes with it.
    await tester.tap(find.text('Monitor'));
    await tester.pump();
    expect(find.text('Needs Monitor on'), findsOneWidget);
    expect(find.text('Add and search'), findsNothing);
    await tester.tap(find.text('Monitor'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Add and search'));
    await _answer(tester);
    final add = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v3/movie')
        .single;
    expect(add.json, containsPair('tmdbId', WorldTitles.metropolis.tmdbId));
    expect(add.json, containsPair('qualityProfileId', 1));
    expect(add.json, containsPair('rootFolderPath', '/mnt/tank/media/films'));
    expect(add.json, containsPair('monitored', true));
    expect(add.json, containsPair('addOptions', {'searchForMovie': true}));
    expect(find.textContaining('Added to Radarr'), findsOneWidget);
    // The sheet is gone, and Radarr is asked again.
    expect(find.text('Instance'), findsNothing);
    expect(
      harness.network
          .requestsTo(WorldIds.radarr)
          .where((r) => r.method == 'GET' && r.uri.path == '/api/v3/movie'),
      hasLength(2),
    );

    await harness.unmount(tester);
  });

  testWidgets('Remove asks what goes with it, then asks Radarr', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);
    final row = find.textContaining(RegExp(r'^Remove from '));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Remove Tears of Steel from Radarr?'), findsOneWidget);
    expect(find.text('Radarr stops looking for it.'), findsOneWidget);
    expect(find.text("Don't add it again"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Remove from Radarr'), findsOne);

    await tester.tap(find.textContaining('Also delete'));
    await tester.pump();
    final confirm = find.ancestor(
      of: find.textContaining(RegExp(r'^Remove and delete 1\.1.GB$')),
      matching: find.byType(FilledButton),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await _answer(tester);

    final delete = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'DELETE')
        .single;
    expect(delete.uri.path, '/api/v3/movie/5');
    expect(delete.uri.queryParameters, {
      'deleteFiles': 'true',
      'addImportExclusion': 'false',
    });
    expect(find.text('Removed from Radarr'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('with two copies, Remove asks which, and says which stays', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);
    final row = find.text('Remove a copy');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    final fourK = find.bySemanticsLabel('Remove from Radarr · 4K');
    expect(find.bySemanticsLabel('Remove from Radarr 1'), findsOneWidget);
    expect(fourK, findsOneWidget);

    await tester.tap(fourK);
    await tester.pumpAndSettle();
    expect(
      find.text('Radarr · 4K stops looking for it. Radarr 1 keeps its copy.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(
      harness.network.requests.where((r) => r.method == 'DELETE'),
      isEmpty,
    );

    await harness.unmount(tester);
  });

  testWidgets('a stuck copy leads with its fault and its remedy', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.bigBuckBunny);

    expect(find.text('Stuck at 47%'), findsOneWidget);
    expect(find.text('Radarr 1 · qBittorrent'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MachineName &&
            widget.name == 'Big.Buck.Bunny.2008.1080p.BluRay',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Try another download'),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r"^Radarr 1 drops this one \(.+ so far\), ")),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove download'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from queue?'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a copy\'s profile and monitoring are changed where they are '
      'read', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);
    await tester.ensureVisible(find.text('Files & quality'));
    await tester.tap(find.text('Files & quality'));
    await _answer(tester);

    expect(find.text('Quality profile'), findsOneWidget);
    expect(find.text('HD-1080p'), findsOneWidget);
    expect(find.text('Grabs it and upgrades it to HD-1080p'), findsOneWidget);

    await tester.tap(find.text('Monitor'));
    await tester.pump();
    // It shows at once, and Radarr is told. (The world keeps nothing: the
    // copy read again after the write says what it always said.)
    expect(find.text('Radarr lists it and never looks for it'), findsOneWidget);
    await _answer(tester);
    final put = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'PUT')
        .single;
    expect(put.uri.path, '/api/v3/movie/5');
    expect(put.json, containsPair('monitored', false));

    await harness.unmount(tester);
  });

  testWidgets('the requester asks for a movie that is not there', (
    tester,
  ) async {
    // In the world Anna has asked for Charge already: here Seerr knows
    // nothing of it yet.
    final harness = await _pump(
      tester,
      Profiles.p2,
      WorldTitles.charge,
      overrides: [
        mediaSeerrRecordProvider.overrideWith(
          (ref, source) async => MediaAnswer(
            const MediaSeerrRecord(
              details: {
                'id': 1011985,
                'title': 'Charge',
                'releaseDate': '2022-10-11',
                'overview': 'A Blender open movie.',
              },
            ),
            DateTime(2026, 10, 4),
          ),
        ),
      ],
    );
    final request = find.widgetWithText(FilledButton, 'Request');
    expect(request, findsOneWidget);
    expect(find.text('Not on the server yet.'), findsOneWidget);
    // No service name but Jellyfin and Plex, no Manage.
    expect(find.textContaining('Radarr'), findsNothing);
    expect(find.text('Manage'), findsNothing);

    await tester.tap(request);
    await _answer(tester);
    expect(find.text('Request Charge'), findsOneWidget);
    expect(find.text('Submit request'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a request that stands is said, and asks nothing', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p2, WorldTitles.metropolis);

    final lead = find.widgetWithText(FilledButton, 'Requested');
    expect(lead, findsOneWidget);
    expect(tester.widget<FilledButton>(lead).onPressed, isNull);
    expect(
      find.textContaining(RegExp(r'^(Waiting for approval|On its way)\.$')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Watchlist puts the title on the list of whom Seerr acts as', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);
    final watchlist = find.widgetWithText(OutlinedButton, 'Watchlist');
    expect(watchlist, findsOneWidget);

    await tester.tap(watchlist);
    await _answer(tester);
    final add = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v1/watchlist')
        .single;
    expect(add.json, {
      'tmdbId': WorldTitles.tearsOfSteel.tmdbId,
      'mediaType': 'movie',
      'title': 'Tears of Steel',
    });
    expect(find.text('On your watchlist'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('on the server by Seerr\'s word: watched in its player', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p2, WorldTitles.tearsOfSteel);

    final watch = find.widgetWithText(FilledButton, 'Watch on Jellyfin');
    expect(watch, findsOneWidget);
    expect(tester.widget<FilledButton>(watch).onPressed, isNotNull);
    expect(find.text('Request'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('Search releases asks which copy when there are two', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Search releases on Radarr 1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Search releases on Radarr · 4K'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Search releases on one copy opens its releases', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Releases'), findsWidgets);

    await harness.unmount(tester);
  });
}

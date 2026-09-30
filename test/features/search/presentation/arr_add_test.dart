import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';

/// The connection the lens is on: first in the list, so nothing has to point it
/// there.
const _home = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: 'Home',
  url: 'http://home.lan:7878',
  credential: 'key-home',
);

/// The connection the row under test came from — deliberately NOT the lens.
///
/// The whole point of the fixture: a sheet that reads the lens instead of the
/// section would still find a configured Radarr, still load profiles, still
/// report success, and would have added the film to the wrong library. The two
/// only tell each other apart because they are different here.
const _away = ServiceInstance(
  id: 'radarr-away111',
  service: ServiceKey.radarr,
  label: 'Away',
  url: 'http://away.lan:7878',
  credential: 'key-away',
);

void main() {
  testWidgets('the plus on an arr row opens a sheet naming its connection', (
    tester,
  ) async {
    final scope = _Scope();
    await _pumpSearch(tester, scope);

    // One plus on screen: the lens's section holds the film already, so its
    // row wears a tick.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Dune'), findsWidgets);
    // The line where the user finds out the choice was already made for them.
    expect(find.text('Adding to Radarr · Away'), findsOneWidget);
    // And no server picker: the section already decided.
    expect(find.text('Server'), findsNothing);
  });

  testWidgets('the add lands on the section, not on the lens', (tester) async {
    final scope = _Scope();
    await _pumpSearch(tester, scope);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(scope.away.added, hasLength(1));
    expect(scope.away.added.single.movie.title, 'Dune');
    // The defaults: first profile, first root folder, monitored, search now —
    // so the common case is two taps.
    expect(scope.away.added.single.qualityProfileId, 3);
    expect(scope.away.added.single.rootFolderPath, '/away/movies');
    expect(scope.away.added.single.monitored, isTrue);
    expect(scope.away.added.single.search, isTrue);
    // The one that makes this test worth writing.
    expect(
      scope.home.added,
      isEmpty,
      reason: 'the lens is a different Radarr from the one that listed the row',
    );
  });

  testWidgets('a successful add turns the row into an owned one', (
    tester,
  ) async {
    final scope = _Scope();
    await _pumpSearch(tester, scope);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // The sheet is gone and the row it was opened from now reads as held.
    expect(find.text('Adding to Radarr · Away'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.text('Added to Radarr · Away'), findsOneWidget);
  });

  testWidgets('a refused add says which connection refused', (tester) async {
    final scope = _Scope(awayRejects: true);
    await _pumpSearch(tester, scope);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Named, because "the add failed" is useless when two Radarr are on
    // screen — and not swallowed, which is D13's lesson.
    expect(
      find.textContaining("Couldn't add Dune to Radarr · Away"),
      findsOneWidget,
    );
    // The row did not lie about the outcome.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('an unreachable connection is not read as an empty one', (
    tester,
  ) async {
    final scope = _Scope(awayOffline: true);
    await _pumpSearch(tester, scope);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    // Not "no root folders configured": the root-folder fetch is the one that
    // travels, so an unreachable server says so rather than looking empty.
    expect(find.text('Radarr · Away did not answer.'), findsOneWidget);
    // The button stays on screen and stays dead: there is nothing honest to
    // post, and hiding it would leave the sheet looking like it was still
    // loading.
    final add = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add'),
    );
    expect(add.onPressed, isNull);
  });
}

class _AddCall {
  final RadarrMovie movie;
  final int qualityProfileId;
  final String rootFolderPath;
  final bool monitored;
  final bool search;

  _AddCall({
    required this.movie,
    required this.qualityProfileId,
    required this.rootFolderPath,
    required this.monitored,
    required this.search,
  });
}

class _Scope {
  final _AddRadarrService home;
  final _AddRadarrService away;

  _Scope({bool awayRejects = false, bool awayOffline = false})
    : home = _AddRadarrService(
        // The lens already holds it, so its row wears a tick and the only plus
        // on screen belongs to the other section.
        results: [_movie(id: 5)],
        profileId: 1,
        rootFolder: '/home/movies',
      ),
      away = _AddRadarrService(
        results: [_movie(id: 0)],
        profileId: 3,
        rootFolder: '/away/movies',
        rejects: awayRejects,
        offline: awayOffline,
      );

  List<Override> get overrides => [
    currentSettingsProvider.overrideWith(
      (ref) => const SettingsModel(instances: [_home, _away]),
    ),
    globalSearchQueryProvider.overrideWith((ref) => 'dune'),
    seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
    radarrServiceProvider.overrideWith((ref) => home),
    radarrServiceForProvider(_away.id).overrideWithValue(away),
  ];
}

Future<void> _pumpSearch(WidgetTester tester, _Scope scope) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: scope.overrides,
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

RadarrMovie _movie({required int id}) => RadarrMovie(
  id: id,
  title: 'Dune',
  sortTitle: 'dune',
  titleSlug: 'dune-438631',
  sizeOnDisk: 0,
  status: 'released',
  hasFile: false,
  monitored: false,
  year: 2021,
  images: const [],
  tmdbId: 438631,
  runtime: 155,
  genres: const [],
);

class _AddRadarrService extends FakeRadarrService {
  final List<RadarrMovie> results;
  final int profileId;
  final String rootFolder;
  final bool rejects;
  final bool offline;
  final List<_AddCall> added = [];

  _AddRadarrService({
    required this.results,
    required this.profileId,
    required this.rootFolder,
    this.rejects = false,
    this.offline = false,
  });

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async => results;

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    if (offline) return const [];
    return [
      {'id': profileId, 'name': 'HD-1080p'},
      {'id': profileId + 1, 'name': 'Ultra-HD'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    if (offline) throw const SocketException('Connection refused');
    return [
      {'id': 1, 'path': rootFolder},
      {'id': 2, 'path': '$rootFolder-4k'},
    ];
  }

  @override
  Future<RadarrMovie> addMovie(
    RadarrMovie movie, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMovie = true,
  }) async {
    if (rejects) throw Exception('400 MovieExistsValidator');
    added.add(
      _AddCall(
        movie: movie,
        qualityProfileId: qualityProfileId,
        rootFolderPath: rootFolderPath,
        monitored: monitored,
        search: searchForMovie,
      ),
    );
    return _movie(id: 99);
  }
}

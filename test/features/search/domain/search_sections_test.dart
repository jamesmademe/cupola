import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/domain/search_sections.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How the lanes of a search fold into its sections: one row per title,
/// whoever found it; on the server by any source's word; addable only on the
/// word of every connection of its arr.
void main() {
  test('one title found by Seerr, Radarr and Jellyfin is one row, on the '
      'server, in Seerr\'s words and TMDB\'s artwork', () {
    final sections = searchSections([
      _lane(ServiceKey.radarr, [
        _hit(ServiceKey.radarr, 'Sintel', key: _sintel, inLibrary: true),
      ]),
      _lane(ServiceKey.seerr, [
        _hit(
          ServiceKey.seerr,
          'Sintel (2010)',
          key: _sintel,
          image: 'https://image.tmdb.org/sintel.jpg',
          score: 7.1,
        ),
      ]),
      _lane(ServiceKey.jellyfin, [
        _hit(ServiceKey.jellyfin, 'Sintel', key: _sintel),
      ]),
    ]);

    final row = sections.onServer.single;
    expect(sections.movies, isEmpty);
    expect(row.title, 'Sintel (2010)');
    expect(row.imageUrl, 'https://image.tmdb.org/sintel.jpg');
    expect(row.score, 7.1);
    expect(row.libraries, ['Radarr']);
    expect(row.servers, ['Jellyfin']);
    // The page opens on the copy that holds it.
    expect(row.route, '/radarr/Sintel');
  });

  test('a title Seerr says is there is on the server with no other word', () {
    final sections = searchSections([
      _lane(ServiceKey.seerr, [
        _hit(
          ServiceKey.seerr,
          'Spring',
          key: const MediaKey.movie(1),
          seerrInfo: const {'status': 4},
        ),
        _hit(
          ServiceKey.seerr,
          'Charge',
          key: const MediaKey.movie(2),
          seerrInfo: const {'status': 3},
        ),
      ]),
    ]);

    // Partly there is there; processing is not yet.
    expect(sections.onServer.map((t) => t.title), ['Spring']);
    expect(sections.movies.map((t) => t.title), ['Charge']);
  });

  test(
    'movies and series apart, people from Seerr, anything else left out',
    () {
      final sections = searchSections([
        _lane(ServiceKey.seerr, [
          _hit(ServiceKey.seerr, 'Cosmos', key: const MediaKey.tv(9)),
          _hit(
            ServiceKey.seerr,
            'Carl Sagan',
            kind: SearchHitKind.person,
            key: null,
          ),
        ]),
        _lane(ServiceKey.jellyfin, [
          _hit(
            ServiceKey.jellyfin,
            'Cosmos: Episode 1',
            kind: SearchHitKind.other,
            key: null,
          ),
        ]),
      ]);

      expect(sections.series.single.title, 'Cosmos');
      expect(sections.people.single.title, 'Carl Sagan');
      expect(sections.peopleAsked, isTrue);
      expect(sections.onServer, isEmpty);
    },
  );

  group('a media server\'s hit with no id', () {
    // Jellyfin's search carries no TMDB id: its Fight Club met nobody and
    // stood beside Seerr's as a second row (the lab, 06/10).
    List<GlobalSearchServiceResults> lanes({int? jellyfinYear}) => [
      _lane(ServiceKey.seerr, [
        _hit(
          ServiceKey.seerr,
          'Fight Club',
          key: const MediaKey.movie(550),
          year: 1999,
        ),
        _hit(
          ServiceKey.seerr,
          'Fight Club',
          key: const MediaKey.movie(1158957),
          year: 2023,
        ),
      ]),
      _lane(ServiceKey.jellyfin, [
        _hit(
          ServiceKey.jellyfin,
          'Fight club',
          key: null,
          kind: SearchHitKind.movie,
          year: jellyfinYear,
        ),
      ]),
    ];

    test('meets the title of the same kind, name and year', () {
      final sections = searchSections(lanes(jellyfinYear: 1999));

      expect(sections.onServer.single.key, const MediaKey.movie(550));
      expect(sections.onServer.single.servers, ['Jellyfin']);
      expect(sections.movies.single.key, const MediaKey.movie(1158957));
    });

    test('with no year and two titles of that name, stays its own row', () {
      final sections = searchSections(lanes());

      expect(sections.onServer.single.key, isNull);
      expect(sections.movies, hasLength(2));
    });
  });

  test('a word Seerr reads as a person leads with the people', () {
    final person = _hit(
      ServiceKey.seerr,
      'Tom Hanks',
      kind: SearchHitKind.person,
      key: null,
    );
    final title = _hit(
      ServiceKey.seerr,
      'The Tom Hanks Story',
      key: const MediaKey.movie(1),
    );

    expect(
      searchSections([
        _lane(ServiceKey.seerr, [person, title]),
      ]).peopleFirst,
      isTrue,
    );
    expect(
      searchSections([
        _lane(ServiceKey.seerr, [title, person]),
      ]).peopleFirst,
      isFalse,
    );
  });

  test('a series Sonarr knows by TVDB alone stays its own row', () {
    final sections = searchSections([
      _lane(ServiceKey.seerr, [
        _hit(ServiceKey.seerr, 'Cosmos', key: const MediaKey.tv(9)),
      ]),
      _lane(ServiceKey.sonarr, [
        _hit(ServiceKey.sonarr, 'Cosmos', key: const MediaKey.tvdb(77)),
      ]),
    ]);

    expect(sections.series, hasLength(2));
  });

  group('the plus', () {
    test('a title no connection of its arr holds, all of them answering', () {
      final sections = searchSections([
        _lane(ServiceKey.radarr, [
          _hit(ServiceKey.radarr, 'Arrival', key: const MediaKey.movie(5)),
        ]),
        _lane(ServiceKey.radarr, const [], name: '4K'),
      ]);

      expect(sections.movies.single.addable, isTrue);
    });

    test('never while a connection of that arr has not answered', () {
      final sections = searchSections([
        _lane(ServiceKey.radarr, [
          _hit(ServiceKey.radarr, 'Arrival', key: const MediaKey.movie(5)),
        ]),
        _lane(
          ServiceKey.radarr,
          const [],
          name: '4K',
          state: SearchLaneState.searching,
        ),
      ]);

      expect(sections.movies.single.addable, isFalse);
      expect(sections.searching, isTrue);
    });

    test('never where its arr is not set up', () {
      final sections = searchSections([
        _lane(ServiceKey.seerr, [
          _hit(ServiceKey.seerr, 'Cosmos', key: const MediaKey.tv(9)),
        ]),
      ]);

      expect(sections.series.single.addable, isFalse);
    });

    test('never on a title the other connection holds', () {
      final sections = searchSections([
        _lane(ServiceKey.radarr, [
          _hit(ServiceKey.radarr, 'Arrival', key: const MediaKey.movie(5)),
        ]),
        _lane(ServiceKey.radarr, [
          _hit(
            ServiceKey.radarr,
            'Arrival',
            key: const MediaKey.movie(5),
            inLibrary: true,
          ),
        ], name: '4K'),
      ]);

      final row = sections.onServer.single;
      expect(row.addable, isFalse);
      expect(row.libraries, ['Radarr\u00A0· 4K']);
    });
  });

  test('a source that stopped is listed once and adds nothing', () {
    final sections = searchSections([
      _lane(ServiceKey.seerr, const [], state: SearchLaneState.unreachable),
      _lane(ServiceKey.radarr, [
        _hit(ServiceKey.radarr, 'Dune', key: const MediaKey.movie(7)),
      ]),
    ]);

    expect(sections.silent.single.service, ServiceKey.seerr);
    expect(sections.peopleAsked, isFalse);
    expect(sections.movies.single.title, 'Dune');
    expect(sections.settled, isTrue);
  });
}

const _sintel = MediaKey.movie(45745);

GlobalSearchServiceResults _lane(
  ServiceKey service,
  List<GlobalSearchResult> results, {
  String name = '',
  SearchLaneState state = SearchLaneState.answered,
}) => GlobalSearchServiceResults(
  leg: (
    instance: ServiceInstance(
      id: '${service.name}$name',
      service: service,
      url: 'http://${service.name}.local',
      credential: 'key',
    ),
    name: name,
  ),
  results: results,
  state: state,
);

GlobalSearchResult _hit(
  ServiceKey service,
  String title, {
  required MediaKey? key,
  SearchHitKind? kind,
  bool inLibrary = false,
  String image = '',
  int? year,
  double? score,
  Map<String, dynamic>? seerrInfo,
}) => GlobalSearchResult(
  service: service,
  id: 0,
  title: title,
  subtitle: '',
  imageUrl: image,
  imageHeaders: null,
  tags: const [],
  route: '/${service.name}/$title',
  heroTag: '${service.name}_$title',
  inLibrary: inLibrary,
  kind:
      kind ??
      (key == null || key.isMovie ? SearchHitKind.movie : SearchHitKind.series),
  key: key,
  year: year,
  score: score,
  seerrInfo: seerrInfo,
);

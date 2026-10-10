/// Everyone's requests on Activity: the latest few that move or arrived, how
/// the rest stand, and one request as one line.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/everyones_requests.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// Friday 9 October 2026, 20:30.
final _now = DateTime(2026, 10, 9, 20, 30);

String _at(Duration before) => _now.subtract(before).toUtc().toIso8601String();
String _ahead(Duration after) => _now.add(after).toUtc().toIso8601String();

/// One request as Seerr sends it. [status] is Seerr's own (1 waiting, 2
/// approved, 3 declined, 4 failed); [media] the title's (3 processing, 5
/// available, 6 blocklisted, 7 deleted).
SeerrRequest _request(
  int id, {
  int status = 2,
  int? media,
  Duration asked = const Duration(hours: 2),
  Duration? answered,
  Duration? added,
  double? progress,
  Duration eta = const Duration(minutes: 40),
}) => SeerrRequest.fromJson({
  'id': id,
  'status': status,
  'type': 'movie',
  'createdAt': _at(asked),
  if (answered != null) 'updatedAt': _at(answered),
  'media': {
    'id': id,
    'tmdbId': 100 + id,
    'mediaType': 'movie',
    'status': ?media,
    'title': 'Title $id',
    if (progress != null)
      'downloadStatus': [
        {
          'size': 1000,
          'sizeLeft': ((1 - progress) * 1000).round(),
          'status': 'downloading',
          'estimatedCompletionTime': _ahead(eta),
        },
      ],
    if (added != null) 'mediaAddedAt': _at(added),
  },
  'requestedBy': {'id': 1, 'displayName': 'Anna'},
}, numbering: SeerrNumbering.seerr);

MyRequests _mine(List<SeerrRequest> requests) =>
    myRequestsOf(requests, now: _now);

List<int> _ids(List<MyRequest> rows) => [
  for (final mine in rows) mine.request.id,
];

void main() {
  group('everyonesLatest', () {
    test('what moves or arrived, newest first, three at most', () {
      final rows = everyonesLatest(
        _mine([
          // Downloading, asked an hour ago.
          _request(1, media: 3, progress: 0.5, asked: const Duration(hours: 1)),
          // Arrived two days ago (asked a week ago).
          _request(
            2,
            media: 5,
            asked: const Duration(days: 7),
            added: const Duration(days: 2),
          ),
          // On its way, asked four hours ago.
          _request(3, media: 3, asked: const Duration(hours: 4)),
          // Arrived an hour ago.
          _request(
            4,
            media: 5,
            asked: const Duration(days: 9),
            added: const Duration(hours: 1),
          ),
        ]),
      );

      // A request that arrived is dated by its arrival, one that moves by
      // its asking.
      expect(_ids(rows), [1, 4, 3]);
    });

    test('a request waiting for an answer is Needs you\'s, a no, a failure '
        'and a removal are the Requests view\'s', () {
      final rows = everyonesLatest(
        _mine([
          _request(1, status: 1),
          _request(2, status: 3),
          _request(3, status: 4),
          _request(4, media: 6),
          _request(5, media: 3, asked: const Duration(hours: 3)),
        ]),
      );

      expect(_ids(rows), [5]);
    });

    test('the limit is the caller\'s', () {
      final requests = _mine([
        for (var id = 1; id <= 5; id++)
          _request(id, media: 3, asked: Duration(hours: id)),
      ]);

      expect(_ids(everyonesLatest(requests, limit: 2)), [1, 2]);
      expect(everyonesRequestsLimit, 3);
      expect(everyonesLatest(requests), hasLength(everyonesRequestsLimit));
      expect(everyonesLatest(requests, limit: 0), isEmpty);
    });

    test('a request with no date goes after the ones that have one', () {
      final undated = SeerrRequest.fromJson({
        'id': 9,
        'status': 2,
        'type': 'movie',
        'createdAt': '',
        'media': {
          'id': 9,
          'tmdbId': 109,
          'mediaType': 'movie',
          'status': 3,
          'title': 'Title 9',
        },
      }, numbering: SeerrNumbering.seerr);

      final rows = everyonesLatest(
        _mine([undated, _request(1, media: 3), _request(2, media: 3)]),
      );

      expect(_ids(rows).last, 9);
      expect(_ids(rows).toSet(), {1, 2, 9});
    });

    test('nothing in, nothing out', () {
      expect(everyonesLatest(_mine(const [])), isEmpty);
    });
  });

  group('everyonesSummary', () {
    test('what is processing and what was declined, said once each', () {
      final requests = _mine([
        _request(1, media: 3, progress: 0.5),
        _request(2, media: 3),
        _request(3, media: 3, progress: 0.9),
        _request(4, status: 3),
        _request(5, status: 3),
      ]);

      expect(everyonesSummary(requests), '3 processing · 2 declined');
    });

    test('either half alone', () {
      expect(everyonesSummary(_mine([_request(1, media: 3)])), '1 processing');
      expect(everyonesSummary(_mine([_request(1, status: 3)])), '1 declined');
    });

    test(
      'every way of being on its way is processing; a finishing one too',
      () {
        final finishing = SeerrRequest.fromJson({
          'id': 6,
          'status': 2,
          'type': 'movie',
          'createdAt': _at(const Duration(hours: 1)),
          'media': {
            'id': 6,
            'tmdbId': 106,
            'mediaType': 'movie',
            'status': 3,
            'title': 'Title 6',
            'downloadStatus': [
              {'size': 1000, 'sizeLeft': 0, 'status': 'completed'},
            ],
          },
        }, numbering: SeerrNumbering.seerr);

        final requests = _mine([
          _request(1, media: 3, progress: 0.4), // downloading
          _request(2, media: 3), // on its way
          finishing,
        ]);
        expect(
          [for (final mine in requests.all) mine.stage],
          containsAll([
            MyRequestStage.downloading,
            MyRequestStage.onItsWay,
            MyRequestStage.finishing,
          ]),
        );
        expect(everyonesSummary(requests), '3 processing');
      },
    );

    test('waiting, arrived, failed and removed are neither', () {
      final requests = _mine([
        _request(1, status: 1),
        _request(2, media: 5, added: const Duration(hours: 1)),
        _request(3, status: 4),
        _request(4, media: 6),
      ]);

      expect(everyonesSummary(requests), isEmpty);
    });

    test('nothing in, nothing said', () {
      expect(everyonesSummary(_mine(const [])), isEmpty);
    });
  });

  group('everyonesLine', () {
    String line(SeerrRequest request) =>
        everyonesLine(myRequestOf(request, now: _now), _now);

    test('downloading: the state, then when it should be ready', () {
      expect(
        line(_request(1, media: 3, progress: 0.62)),
        'Downloading 62% · ready around 21:10',
      );
    });

    test('on the server: since when, after the state', () {
      expect(
        line(_request(1, media: 5, added: const Duration(hours: 2))),
        'Ready to watch since 18:30',
      );
      expect(
        line(_request(1, media: 5, added: const Duration(days: 27))),
        'On the server since 12 Sep',
      );
    });

    test('an answer says when it was given, in the owner\'s words', () {
      // Never the requester's "declined by the server's owner": the one
      // reading is the owner.
      expect(
        line(_request(1, status: 3, answered: const Duration(hours: 3))),
        'Declined today',
      );
      expect(
        line(_request(1, status: 3, answered: const Duration(days: 1))),
        'Declined yesterday',
      );
      expect(
        line(_request(1, status: 4, answered: const Duration(days: 3))),
        "Didn't go through on Tuesday",
      );
      expect(
        line(_request(1, status: 3, answered: const Duration(days: 30))),
        'Declined on 9 Sep',
      );
    });

    test('a state with nothing to add is the state alone', () {
      expect(line(_request(1, media: 6)), 'Blocked');
      expect(line(_request(1, media: 7)), 'Removed from the server');
    });

    test('a detail the state already says is not said twice', () {
      final request = _request(1, media: 5);
      final mine = myRequestOf(request, now: _now);
      // No arrival time known: the detail is the state's own word.
      expect(mine.detail(_now), mine.state);
      expect(everyonesLine(mine, _now), mine.state);
    });

    test('the detail leads in the lower case after a middle dot', () {
      expect(line(_request(1, media: 3)), 'On its way · being fetched');
    });
  });

  group('everyonesTone', () {
    test('a request that did not go through is the operator\'s fault to '
        'mend: amber', () {
      expect(everyonesTone(MyRequestStage.didNotGoThrough), StatusTone.warning);
    });

    test('every other stage keeps the household\'s tone', () {
      for (final stage in MyRequestStage.values) {
        if (stage == MyRequestStage.didNotGoThrough) continue;
        expect(everyonesTone(stage), stage.tone, reason: '$stage');
      }
    });
  });
}

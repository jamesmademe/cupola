import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// Friday 9 October 2026, 20:30.
final _now = DateTime(2026, 10, 9, 20, 30);

String _at(Duration before) => _now.subtract(before).toUtc().toIso8601String();
String _ahead(Duration after) => _now.add(after).toUtc().toIso8601String();

SeerrRequest _request({
  int id = 1,
  int status = 2,
  int? media,
  int? media4k,
  bool is4k = false,
  Duration asked = const Duration(hours: 2),
  Duration? answered,
  Duration? added,
  List<Map<String, Object?>> downloads = const [],
  String? mediaUrl,
}) => SeerrRequest.fromJson({
  'id': id,
  'status': status,
  'type': 'movie',
  'is4k': is4k,
  'createdAt': _at(asked),
  if (answered != null) 'updatedAt': _at(answered),
  'media': {
    'id': id,
    'tmdbId': 100 + id,
    'mediaType': 'movie',
    'status': ?media,
    'status4k': ?media4k,
    'title': 'Title $id',
    'posterPath': '/p$id.jpg',
    'downloadStatus': is4k ? const [] : downloads,
    'downloadStatus4k': is4k ? downloads : const [],
    'mediaUrl': ?mediaUrl,
    if (added != null) 'mediaAddedAt': _at(added),
  },
}, numbering: SeerrNumbering.seerr);

Map<String, Object?> _download({
  int size = 1000,
  int left = 380,
  String status = 'downloading',
  Duration? eta = const Duration(minutes: 40),
}) => {
  'size': size,
  'sizeLeft': left,
  'status': status,
  'title': 'Some.Release.Name.2160p',
  if (eta != null) 'estimatedCompletionTime': _ahead(eta),
};

MyRequest _read(SeerrRequest request, {bool stale = false}) =>
    myRequestOf(request, now: _now, stale: stale);

void main() {
  group('where a request stands', () {
    test('waiting: when she asked and the copy she asked for', () {
      final mine = _read(_request(status: 1, media: 2));
      expect(mine.stage, MyRequestStage.waiting);
      expect(mine.state, 'Waiting for approval');
      expect(mine.detail(_now), 'Asked 2\u00A0h ago · Standard');
      expect(mine.stage.tone, StatusTone.info);
      expect(mine.watchAt, isNull);

      final yesterday = _read(
        _request(status: 1, is4k: true, asked: const Duration(hours: 30)),
      );
      expect(yesterday.detail(_now), 'Asked yesterday · 4K');
    });

    test('downloading: the figure and when it should be ready', () {
      final mine = _read(_request(media: 3, downloads: [_download()]));
      expect(mine.stage, MyRequestStage.downloading);
      expect(mine.figure, '62%');
      expect(mine.state, 'Downloading 62%');
      expect(mine.stateShort, '62%');
      expect(mine.detail(_now), 'Ready around 21:10');
      expect(mine.progress, closeTo(0.62, 0.001));
    });

    test('a series downloads as one: bytes together, the last to end', () {
      final mine = _read(
        _request(
          media: 4,
          downloads: [
            _download(size: 1000, left: 120, eta: const Duration(minutes: 1)),
            _download(size: 1000, left: 910, eta: const Duration(hours: 5)),
          ],
        ),
      );
      expect(mine.figure, '49%');
      expect(mine.detail(_now), 'Ready around tomorrow 01:30');
    });

    test('a download that does not move is on its way, never stuck', () {
      for (final status in ['warning', 'failed', 'paused', 'queued']) {
        final mine = _read(
          _request(media: 3, downloads: [_download(status: status)]),
        );
        expect(mine.stage, MyRequestStage.onItsWay, reason: status);
        expect(mine.state, 'On its way');
        expect(mine.detail(_now), 'Being fetched');
        expect(mine.progress, isNull);
      }
      // One moving beside one that is not: still no figure.
      final mixed = _read(
        _request(
          media: 3,
          downloads: [
            _download(),
            _download(status: 'warning'),
          ],
        ),
      );
      expect(mixed.stage, MyRequestStage.onItsWay);
      // Nothing Seerr can see.
      expect(_read(_request(media: 3)).stage, MyRequestStage.onItsWay);
    });

    test('a download with no time says it is being fetched', () {
      final mine = _read(_request(media: 3, downloads: [_download(eta: null)]));
      expect(mine.stage, MyRequestStage.downloading);
      expect(mine.detail(_now), 'Being fetched');
    });

    test('downloaded and being put in place', () {
      final mine = _read(
        _request(media: 3, downloads: [_download(status: 'completed')]),
      );
      expect(mine.stage, MyRequestStage.finishing);
      expect(mine.state, 'Finishing on the server');
    });

    test('a list read before the server went quiet claims no figure', () {
      final mine = _read(
        _request(media: 3, downloads: [_download()]),
        stale: true,
      );
      expect(mine.stage, MyRequestStage.onItsWay);
      expect(mine.figure, isNull);
    });

    test('arrived in the last seven days: ready to watch, with its link', () {
      final mine = _read(
        _request(
          media: 5,
          added: const Duration(hours: 1, minutes: 50),
          mediaUrl: 'https://jf.example/web/#/details?id=1',
        ),
      );
      expect(mine.stage, MyRequestStage.readyToWatch);
      expect(mine.state, 'Ready to watch');
      expect(mine.detail(_now), 'Since 18:40');
      expect(mine.stage.tone, StatusTone.success);
      expect(mine.watchAt, Uri.parse('https://jf.example/web/#/details?id=1'));
    });

    test('arrived long ago: on the server, since its day', () {
      final mine = _read(_request(media: 5, added: const Duration(days: 25)));
      expect(mine.stage, MyRequestStage.onTheServer);
      expect(mine.detail(_now), 'Since Mon 14 Sep');
      final days = _read(_request(media: 5, added: const Duration(days: 3)));
      expect(days.stage, MyRequestStage.readyToWatch);
      expect(days.detail(_now), 'Since Tuesday');
    });

    test('a 4K request reads the 4K copy', () {
      // On the server in HD, the 4K copy still coming.
      final mine = _read(
        _request(
          media: 5,
          media4k: 3,
          is4k: true,
          added: const Duration(days: 1),
          downloads: [_download()],
        ),
      );
      expect(mine.stage, MyRequestStage.downloading);
      expect(mine.quality, '4K');
    });

    test('answers are neutral', () {
      final declined = _read(
        _request(status: 3, answered: const Duration(days: 1)),
      );
      expect(declined.stage, MyRequestStage.declined);
      expect(declined.state, 'Declined');
      expect(declined.detail(_now), "Declined by the server's owner");
      expect(declined.stage.tone, StatusTone.neutral);

      final failed = _read(_request(status: 4));
      expect(failed.stage, MyRequestStage.didNotGoThrough);
      expect(failed.state, "Didn't go through");
      expect(failed.stage.tone, StatusTone.neutral);
    });

    test('a title whose files went, or that was barred', () {
      expect(_read(_request(media: 7)).stage, MyRequestStage.removed);
      expect(_read(_request(media: 6)).stage, MyRequestStage.blocked);
    });

    test('the Home line under Ready to watch: when she asked, the score', () {
      final mine = _read(_request(media: 5, asked: const Duration(days: 5)));
      expect(mine.askedLine(_now), 'You asked for it on Sunday');
    });
  });

  group('her list', () {
    final list = myRequestsOf([
      _request(id: 1, media: 5, added: const Duration(days: 20)),
      _request(id: 2, status: 1, asked: const Duration(hours: 5)),
      _request(id: 3, media: 3, downloads: [_download()]),
      _request(id: 4, media: 5, added: const Duration(days: 1)),
      _request(id: 5, status: 3, answered: const Duration(days: 2)),
      _request(id: 6, status: 1, asked: const Duration(minutes: 5)),
      _request(id: 7, media: 3),
      _request(id: 8, status: 3, answered: const Duration(days: 9)),
    ], now: _now);

    test('moves first, then waits, then arrived, answered, long there', () {
      expect(
        [for (final mine in list.all) mine.request.id],
        [
          3, 7, 6, 2, 4, 5, 8, 1, //
        ],
      );
    });

    test('what each part draws', () {
      expect([for (final mine in list.ready) mine.request.id], [4]);
      expect([for (final mine in list.onTheWay) mine.request.id], [3, 7, 6, 2]);
      expect([for (final mine in list.waiting) mine.request.id], [6, 2]);
      expect(
        [for (final mine in list.rest) mine.request.id],
        [3, 7, 4, 5, 8, 1],
      );
    });

    test('the Home lists what is coming and a no of the last week', () {
      expect(
        [for (final mine in list.homeRows(_now)) mine.request.id],
        [
          3, 7, 6, 2, 5, //
        ],
      );
    });
  });

  group('the words for a day', () {
    test('asked', () {
      expect(askedWords(_now, now: _now), 'just now');
      expect(
        askedWords(_now.subtract(const Duration(days: 3)), now: _now),
        'on Tuesday',
      );
      expect(askedWords(DateTime(2025, 12, 2), now: _now), 'on Tue 2 Dec 2025');
    });

    test('ready around', () {
      expect(aroundWords(DateTime(2026, 10, 9, 23, 5), now: _now), '23:05');
      expect(
        aroundWords(DateTime(2026, 10, 10, 9, 10), now: _now),
        'tomorrow 09:10',
      );
      expect(aroundWords(DateTime(2026, 10, 12, 9, 10), now: _now), 'Monday');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';

TvSeason _season(int number, {int episodes = 8}) => TvSeason(
  id: number,
  seasonNumber: number,
  name: 'Season $number',
  episodeCount: episodes,
);

Map<String, dynamic> _request(
  int status, {
  List<int>? seasons,
  bool is4k = false,
}) => {
  'id': 9,
  'status': status,
  'is4k': is4k,
  if (seasons != null)
    'seasons': [
      for (final season in seasons) {'seasonNumber': season, 'status': status},
    ],
};

SeerrRequestState _movie(
  Map<String, dynamic>? mediaInfo, {
  SeerrNumbering? numbering = SeerrNumbering.seerr,
}) => seerrRequestGate(mediaInfo, isMovie: true, numbering: numbering).state;

void main() {
  group('a film', () {
    test('Seerr has no record of: open', () {
      expect(_movie(null), SeerrRequestState.open);
    });

    test('a row Seerr knows nothing on: open', () {
      // The row alone used to disable Request.
      expect(_movie({'id': 1, 'status': 1}), SeerrRequestState.open);
    });

    test('deleted, in either numbering: open', () {
      // Overseerr's DELETED is 6; Seerr's is 7, with 6 for BLOCKLISTED.
      expect(
        _movie({'id': 1, 'status': 6}, numbering: SeerrNumbering.overseerr),
        SeerrRequestState.open,
      );
      expect(_movie({'id': 1, 'status': 7}), SeerrRequestState.open);
    });

    test('blocklisted in Seerr: not requestable, whatever was asked', () {
      expect(_movie({'id': 1, 'status': 6}), SeerrRequestState.blocklisted);
      // Seerr refuses the title, not the request: an old one changes nothing.
      expect(
        _movie({
          'id': 1,
          'status': 6,
          'requests': [_request(4)],
        }),
        SeerrRequestState.blocklisted,
      );
    });

    test('before the server has said, a 6 leaves Request open', () {
      // Barred or deleted: Seerr itself refuses a barred title, and a
      // deleted one is the user's to ask for again.
      expect(
        _movie({'id': 1, 'status': 6}, numbering: null),
        SeerrRequestState.open,
      );
    });

    test('available: not requestable', () {
      expect(_movie({'id': 1, 'status': 5}), SeerrRequestState.available);
    });

    test('pending or processing with no request on the row', () {
      expect(
        _movie({'id': 1, 'status': 2}),
        SeerrRequestState.waitingForApproval,
      );
      expect(_movie({'id': 1, 'status': 3}), SeerrRequestState.onItsWay);
    });

    test('an active request is what Seerr refuses a second one over', () {
      expect(
        _movie({
          'id': 1,
          'status': 7,
          'requests': [_request(1)],
        }),
        SeerrRequestState.waitingForApproval,
      );
      expect(
        _movie({
          'id': 1,
          'status': 1,
          'requests': [_request(2)],
        }),
        SeerrRequestState.onItsWay,
      );
      expect(
        _movie({
          'id': 1,
          'status': 1,
          'requests': [_request(4)],
        }),
        SeerrRequestState.failed,
      );
    });

    test('a declined or completed request does not count', () {
      expect(
        _movie({
          'id': 1,
          'status': 7,
          'requests': [_request(3), _request(5)],
        }),
        SeerrRequestState.open,
      );
    });

    test('a 4K request does not count against the standard one', () {
      expect(
        _movie({
          'id': 1,
          'status': 1,
          'status4k': 3,
          'requests': [_request(2, is4k: true)],
        }),
        SeerrRequestState.open,
      );
    });

    test('the request\'s own status is read, never the media\'s stand-in', () {
      // A pending request on a title Radarr already holds: the media says
      // available, which is the answer for the button too.
      expect(
        _movie({
          'id': 1,
          'status': 5,
          'requests': [_request(1)],
        }),
        SeerrRequestState.available,
      );
    });
  });

  group('a series', () {
    final seasons = [_season(1), _season(2), _season(3)];

    SeerrRequestGate gate(
      Map<String, dynamic>? mediaInfo, {
      SeerrNumbering numbering = SeerrNumbering.seerr,
    }) => seerrRequestGate(
      mediaInfo,
      isMovie: false,
      seasons: seasons,
      numbering: numbering,
    );

    test('blocklisted in Seerr: no season can be asked for', () {
      final result = gate({
        'id': 1,
        'status': 6,
        'seasons': [
          {'seasonNumber': 1, 'status': 6},
        ],
      });
      expect(result.state, SeerrRequestState.blocklisted);
      expect(result.missingSeasons, isEmpty);
    });

    test('an Overseerr season deleted as 6 can be asked for again', () {
      final result = gate({
        'id': 1,
        'status': 4,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 5},
          {'seasonNumber': 3, 'status': 6},
        ],
      }, numbering: SeerrNumbering.overseerr);
      expect(result.state, SeerrRequestState.open);
      expect(result.missingSeasons, [3]);
    });

    test('nothing held: open, with no seasons to name', () {
      final result = gate(null);
      expect(result.state, SeerrRequestState.open);
      expect(result.missingSeasons, isEmpty);
    });

    test('partly available: open for the seasons still missing', () {
      final result = gate({
        'id': 1,
        'status': 4,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 4},
        ],
      });
      expect(result.state, SeerrRequestState.open);
      expect(result.missingSeasons, [3]);
    });

    test('a season asked for already is not missing', () {
      final result = gate({
        'id': 1,
        'status': 4,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
        ],
        'requests': [
          _request(2, seasons: [2]),
        ],
      });
      expect(result.state, SeerrRequestState.open);
      expect(result.missingSeasons, [3]);
    });

    test('a deleted season can be asked for again', () {
      final result = gate({
        'id': 1,
        'status': 4,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 5},
          {'seasonNumber': 3, 'status': 7},
        ],
      });
      expect(result.state, SeerrRequestState.open);
      expect(result.missingSeasons, [3]);
    });

    test('every season on disk: available', () {
      expect(
        gate({
          'id': 1,
          'status': 5,
          'seasons': [
            for (final s in [1, 2, 3]) {'seasonNumber': s, 'status': 5},
          ],
        }).state,
        SeerrRequestState.available,
      );
    });

    test('a new season Seerr has not filed yet is requestable', () {
      expect(
        gate({
          'id': 1,
          'status': 5,
          'seasons': [
            for (final s in [1, 2]) {'seasonNumber': s, 'status': 5},
          ],
        }).missingSeasons,
        [3],
      );
    });

    test('the rest waiting for approval', () {
      expect(
        gate({
          'id': 1,
          'status': 4,
          'seasons': [
            {'seasonNumber': 1, 'status': 5},
          ],
          'requests': [
            _request(1, seasons: [2, 3]),
          ],
        }).state,
        SeerrRequestState.waitingForApproval,
      );
    });

    test('the rest on its way', () {
      expect(
        gate({
          'id': 1,
          'status': 3,
          'seasons': [
            {'seasonNumber': 1, 'status': 5},
            {'seasonNumber': 2, 'status': 3},
            {'seasonNumber': 3, 'status': 3},
          ],
        }).state,
        SeerrRequestState.onItsWay,
      );
    });

    test('the rest covered only by a failed request', () {
      expect(
        gate({
          'id': 1,
          'status': 4,
          'seasons': [
            {'seasonNumber': 1, 'status': 5},
          ],
          'requests': [
            _request(4, seasons: [2, 3]),
          ],
        }).state,
        SeerrRequestState.failed,
      );
    });

    test('specials and empty seasons are not Seerr\'s to request', () {
      final result = seerrRequestGate(
        {
          'id': 1,
          'status': 5,
          'seasons': [
            {'seasonNumber': 1, 'status': 5},
          ],
        },
        isMovie: false,
        seasons: [_season(0), _season(1), _season(2, episodes: 0)],
      );
      expect(result.state, SeerrRequestState.available);
    });

    test('no season list falls back to the title\'s own code', () {
      SeerrRequestState bare(int? code) =>
          seerrRequestGate({'id': 1, 'status': ?code}, isMovie: false).state;
      expect(bare(null), SeerrRequestState.open);
      expect(bare(7), SeerrRequestState.open);
      expect(bare(4), SeerrRequestState.available);
      expect(bare(2), SeerrRequestState.waitingForApproval);
      expect(bare(3), SeerrRequestState.onItsWay);
    });
  });

  group('the 4K copy, on a Seerr with a 4K server', () {
    SeerrRequestGate film(Map<String, dynamic> mediaInfo, {bool uhd = true}) =>
        seerrRequestGate(
          mediaInfo,
          isMovie: true,
          numbering: SeerrNumbering.seerr,
          has4kServer: uhd,
        );

    test('a film on disk in HD only can still be asked for in 4K', () {
      final gate = film({'id': 1, 'status': 5, 'status4k': 1});

      // It read Available, and Request was closed.
      expect(gate.state, SeerrRequestState.open);
      expect(gate.copies, SeerrRequestCopies.uhd);
    });

    test('without a 4K server it closes as it always did', () {
      final gate = film({'id': 1, 'status': 5, 'status4k': 1}, uhd: false);

      expect(gate.state, SeerrRequestState.available);
      expect(gate.copies, SeerrRequestCopies.none);
    });

    test('both copies on disk: closed, with the standard reason', () {
      final gate = film({'id': 1, 'status': 5, 'status4k': 5});

      expect(gate.state, SeerrRequestState.available);
      expect(gate.copies, SeerrRequestCopies.none);
    });

    test('on disk in HD and asked for in 4K: closed', () {
      final gate = film({
        'id': 1,
        'status': 5,
        'status4k': 2,
        'requests': [_request(1, is4k: true)],
      });

      expect(gate.state, SeerrRequestState.available);
      expect(gate.copies, SeerrRequestCopies.none);
    });

    test('neither copy held: either may be asked for', () {
      expect(
        film({'id': 1, 'status': 1, 'status4k': 1}).copies,
        SeerrRequestCopies.both,
      );
      expect(film(const {}).copies, SeerrRequestCopies.both);
    });

    test('on disk in 4K only: the standard copy is open, the 4K one not', () {
      final gate = film({'id': 1, 'status': 1, 'status4k': 5});

      expect(gate.state, SeerrRequestState.open);
      expect(gate.copies, SeerrRequestCopies.standard);
    });

    test('a blocklisted title takes no request in either copy', () {
      final gate = film({'id': 1, 'status': 6, 'status4k': 1});

      expect(gate.state, SeerrRequestState.blocklisted);
      expect(gate.copies, SeerrRequestCopies.none);
    });

    test('a series held in HD reads its seasons in 4K', () {
      final gate = seerrRequestGate(
        {
          'id': 1,
          'status': 5,
          'status4k': 4,
          'seasons': [
            for (var number = 1; number <= 3; number++)
              {
                'seasonNumber': number,
                'status': 5,
                'status4k': number == 1 ? 5 : 1,
              },
          ],
        },
        isMovie: false,
        seasons: [_season(1), _season(2), _season(3)],
        numbering: SeerrNumbering.seerr,
        has4kServer: true,
      );

      expect(gate.state, SeerrRequestState.open);
      expect(gate.copies, SeerrRequestCopies.uhd);
      expect(gate.missingSeasons, [2, 3]);
    });
  });
}

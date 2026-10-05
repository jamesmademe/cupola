/// A media server Cupola does not have, known through Seerr: its row, and
/// the Watch that opens Seerr's link; and a request for a series' seasons,
/// in the words of the card that answers it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/media/domain/media_facts.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';
import 'media_test_helpers.dart';

MediaRowView _view(MediaRow row) => mediaRowView(
  row,
  title: (connection) => connection.service.title,
  now: DateTime(2026, 10, 5),
)!;

void main() {
  group('P3, no media server of its own', () {
    test('a movie on the server by Seerr\'s word: Jellyfin through Seerr '
        'comes first, and Watch on it leads', () async {
      final rows = (await settledRows(
        Profiles.p3,
        WorldTitles.tearsOfSteel,
      )).rows;

      final claim = rows.first as MediaServerThroughSeerrRow;
      expect(claim.server, ServiceKey.jellyfin);
      expect(claim.url.toString(), contains('jf-tearsOfSteel'));
      final view = _view(claim);
      expect(
        (view.name, view.via, view.detail, view.state, view.action),
        (
          'Jellyfin',
          'through Seerr',
          '',
          'Available',
          'Add Jellyfin to Cupola',
        ),
      );
      expect(view.tone, StatusTone.success);

      final lead = resolveMediaLead(rows, audience: Audience.operator);
      expect(lead, isA<MediaLeadWatch>());
      expect((lead as MediaLeadWatch).server, ServiceKey.jellyfin);
    });

    test('a series in part: the row says which seasons', () async {
      final rows = (await settledRows(
        Profiles.p3,
        WorldTitles.cosmosLaundromat,
      )).rows;

      final view = _view(rows.whereType<MediaServerThroughSeerrRow>().single);
      expect(view.detail, 'S1 available · S2 partly available');
      expect(view.state, 'Partial');
      expect(
        resolveMediaLead(rows, audience: Audience.operator),
        isA<MediaLeadWatch>(),
      );
    });

    test('nothing on the server yet: no claim, no Watch', () async {
      final rows = (await settledRows(Profiles.p3, WorldTitles.charge)).rows;

      expect(rows.whereType<MediaServerThroughSeerrRow>(), isEmpty);
    });

    test('the requester asks: the claim is never hers to lead', () async {
      final rows = (await settledRows(
        Profiles.p3,
        WorldTitles.tearsOfSteel,
      )).rows;

      expect(
        resolveMediaLead(rows, audience: Audience.requester),
        isA<MediaLeadRequest>(),
      );
    });
  });

  test('with Jellyfin in Cupola, Seerr\'s link never stands in for it, even '
      'while Jellyfin is silent', () async {
    final rows = (await settledRows(
      Profiles.p7,
      WorldTitles.tearsOfSteel,
    )).rows;

    expect(rows.whereType<MediaServerThroughSeerrRow>(), isEmpty);
    expect(
      resolveMediaLead(rows, audience: Audience.operator),
      isNot(isA<MediaLeadWatch>()),
    );
  });

  test('a series\' seasons as Seerr has them, the 4K copy\'s on its own', () {
    final line = mediaSeerrSeasonsLine({
      'status': 4,
      'seasons': [
        {'seasonNumber': 2, 'status': 4, 'status4k': 5},
        {'seasonNumber': 1, 'status': 5, 'status4k': 5},
        {'seasonNumber': 3, 'status': 2, 'status4k': 1},
        {'seasonNumber': 0, 'status': 5, 'status4k': 1},
      ],
    });
    expect(line, 'S1 available · S2 partly available');
    expect(
      mediaSeerrSeasonsLine({
        'seasons': [
          {'seasonNumber': 1, 'status': 5, 'status4k': 5},
          {'seasonNumber': 2, 'status': 4, 'status4k': 5},
        ],
      }, is4k: true),
      'S1 available · S2 available',
    );
    expect(mediaSeerrSeasonsLine({'status': 5}), '');
  });

  group('a request\'s card names what was asked for', () {
    SeerrRequest request({
      String type = 'tv',
      List<int> seasons = const [],
      bool is4k = false,
    }) => SeerrRequest(
      id: 1,
      status: RequestStatus.pendingApproval,
      type: type,
      createdAt: '2026-10-05T10:00:00.000Z',
      is4k: is4k,
      seasons: [
        for (final number in seasons)
          RequestSeason(seasonNumber: number, status: '1'),
      ],
    );

    test('a series, its seasons', () {
      expect(
        mediaDecisionHeadline(request(seasons: [3]), who: 'Luca'),
        'Luca asked for Season 3',
      );
      expect(
        mediaDecisionHeadline(
          request(seasons: [3, 2], is4k: true),
          who: 'Anna',
        ),
        'Anna asked for Seasons 2 and 3 in 4K',
      );
      expect(
        mediaDecisionHeadline(request(seasons: [3])),
        'Season 3 requested',
      );
    });

    test('a movie, or a series without its seasons, as before', () {
      expect(
        mediaDecisionHeadline(request(type: 'movie', is4k: true), who: 'Anna'),
        'Anna asked for it in 4K',
      );
      expect(mediaDecisionHeadline(request()), 'Requested');
    });
  });

  test('seasons in a sentence, in order and each once', () {
    expect(Lexicon.seasons([2]), 'Season 2');
    expect(Lexicon.seasons([3, 2]), 'Seasons 2 and 3');
    expect(Lexicon.seasons([4, 1, 3, 1]), 'Seasons 1, 3 and 4');
  });
}

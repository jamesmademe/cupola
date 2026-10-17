/// The words of a download on Activity: which way its bytes travel, how long
/// nothing has arrived, when a waiting one starts, and who asked for it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Friday 9 October 2026, 20:00, on this device's clock.
final _now = DateTime(2026, 10, 9, 20);

ServiceQueueItem _item({
  ServiceKey service = ServiceKey.radarr,
  ServiceKey? client = ServiceKey.qbittorrent,
  String clientLabel = 'qBittorrent',
  String? connectionName,
  int? etaSeconds,
  bool queued = false,
  int? tmdbId,
  int? tvdbId,
}) => ServiceQueueItem(
  service: service,
  id: '1',
  title: 'Title',
  progress: 0.5,
  clientLabel: clientLabel,
  clientService: client,
  connectionName: connectionName,
  etaSeconds: etaSeconds,
  queued: queued,
  tmdbId: tmdbId,
  tvdbId: tvdbId,
);

SeerrRequest _request({
  int id = 1,
  String type = 'movie',
  RequestStatus status = RequestStatus.approved,
  int? tmdbId,
  int? tvdbId,
  String? who = 'Anna',
  bool withMedia = true,
}) => SeerrRequest(
  id: id,
  status: status,
  type: type,
  createdAt: '2026-10-09T10:00:00.000Z',
  media: withMedia
      ? RequestMedia(title: 'Title', tmdbId: tmdbId, tvdbId: tvdbId)
      : null,
  requestedBy: who == null ? null : RequestedBy(id: 1, displayName: who),
);

void main() {
  group('downloadRoute', () {
    test('who asked and who moves the bytes', () {
      expect(downloadRoute(_item()), 'Radarr → qBittorrent');
      expect(
        downloadRoute(
          _item(
            service: ServiceKey.sonarr,
            client: ServiceKey.sabnzbd,
            clientLabel: 'SABnzbd',
          ),
        ),
        'Sonarr → SABnzbd',
      );
    });

    test('a second connection of the arr says which', () {
      expect(
        downloadRoute(
          _item(
            client: ServiceKey.sabnzbd,
            clientLabel: 'SABnzbd',
            connectionName: '4K',
          ),
        ),
        'Radarr 4K → SABnzbd',
      );
    });

    test('a transfer no arr asked for is its client alone', () {
      expect(
        downloadRoute(
          _item(
            service: ServiceKey.qbittorrent,
            client: ServiceKey.qbittorrent,
          ),
        ),
        'qBittorrent',
      );
    });

    test('with no client matched it is the label the arr holds, or the arr '
        'itself', () {
      expect(downloadRoute(_item(client: null)), 'qBittorrent');
      expect(downloadRoute(_item(client: null, clientLabel: '')), 'Radarr');
      expect(
        downloadRoute(
          _item(service: ServiceKey.qbittorrent, client: null, clientLabel: ''),
        ),
        'qBittorrent',
      );
    });
  });

  group('nothingForWords', () {
    String? words(Duration idle) =>
        nothingForWords(_now.subtract(idle), now: _now);

    test('the client dated nothing: nothing is claimed', () {
      expect(nothingForWords(null, now: _now), isNull);
    });

    test('a moment in the future is no idle time', () {
      expect(
        nothingForWords(_now.add(const Duration(minutes: 1)), now: _now),
        isNull,
      );
    });

    test('minutes under the hour, then hours, then days from the second '
        'day', () {
      expect(words(Duration.zero), 'nothing for 0\u00A0min');
      expect(words(const Duration(minutes: 40)), 'nothing for 40\u00A0min');
      expect(
        words(const Duration(minutes: 59, seconds: 59)),
        'nothing for 59\u00A0min',
      );
      expect(words(const Duration(hours: 1)), 'nothing for 1\u00A0h');
      expect(words(const Duration(hours: 3)), 'nothing for 3\u00A0h');
      // A day and a half is hours: 'days' starts at the second day.
      expect(
        words(const Duration(hours: 47, minutes: 59)),
        'nothing for 47\u00A0h',
      );
      expect(words(const Duration(days: 2)), 'nothing for 2 days');
      expect(words(const Duration(days: 9, hours: 5)), 'nothing for 9 days');
    });
  });

  group('queuedWords', () {
    test('where the client estimates it, when it starts', () {
      expect(queuedWords(360), 'Queued\u00A0· starts in about 6\u00A0min');
      expect(
        queuedWords(5400),
        'Queued\u00A0· starts in about 1\u00A0h 30\u00A0min',
      );
    });

    test('where it does not, or it already should have, just Queued', () {
      expect(queuedWords(null), 'Queued');
      expect(queuedWords(0), 'Queued');
      expect(queuedWords(-30), 'Queued');
    });
  });

  group('requestFor', () {
    test('a Radarr download is the movie request with its TMDB id', () {
      final request = _request(tmdbId: 811631);
      expect(
        requestFor(_item(tmdbId: 811631), [
          _request(id: 2, tmdbId: 7),
          request,
        ]),
        request,
      );
    });

    test('a Sonarr download is the series request by TVDB, or by TMDB when '
        'TVDB is not there', () {
      final byTvdb = _request(type: 'tv', tvdbId: 300001);
      final byTmdb = _request(id: 2, type: 'tv', tmdbId: 358332);

      expect(
        requestFor(
          _item(service: ServiceKey.sonarr, tvdbId: 300001, tmdbId: 1),
          [byTmdb, byTvdb],
        ),
        byTvdb,
      );
      expect(
        requestFor(_item(service: ServiceKey.sonarr, tmdbId: 358332), [
          byTvdb,
          byTmdb,
        ]),
        byTmdb,
      );
    });

    test('a movie is not a series with the same number', () {
      expect(
        requestFor(_item(tmdbId: 5), [_request(type: 'tv', tmdbId: 5)]),
        isNull,
      );
      expect(
        requestFor(_item(service: ServiceKey.sonarr, tmdbId: 5), [
          _request(tmdbId: 5),
        ]),
        isNull,
      );
    });

    test('a request that was declined or failed asked for nothing that is '
        'coming', () {
      for (final status in [RequestStatus.declined, RequestStatus.failed]) {
        expect(
          requestFor(_item(tmdbId: 5), [_request(tmdbId: 5, status: status)]),
          isNull,
          reason: '$status',
        );
      }
      // Waiting, approved and completed all can have brought a download.
      for (final status in [
        RequestStatus.pendingApproval,
        RequestStatus.approved,
        RequestStatus.completed,
      ]) {
        expect(
          requestFor(_item(tmdbId: 5), [_request(tmdbId: 5, status: status)]),
          isNotNull,
          reason: '$status',
        );
      }
    });

    test('nothing is matched without a title\'s id, or off a service that is '
        'no arr of movies or series', () {
      expect(requestFor(_item(), [_request(tmdbId: 5)]), isNull);
      expect(
        requestFor(_item(service: ServiceKey.sonarr), [
          _request(type: 'tv', tmdbId: 5, tvdbId: 6),
        ]),
        isNull,
      );
      for (final service in [
        ServiceKey.lidarr,
        ServiceKey.readarr,
        ServiceKey.qbittorrent,
        ServiceKey.sabnzbd,
      ]) {
        expect(
          requestFor(_item(service: service, tmdbId: 5), [_request(tmdbId: 5)]),
          isNull,
          reason: service.name,
        );
      }
    });

    test('a request that names no media is skipped; none at all is null', () {
      expect(
        requestFor(_item(tmdbId: 5), [_request(withMedia: false)]),
        isNull,
      );
      expect(requestFor(_item(tmdbId: 5), const []), isNull);
    });
  });

  group('requestLine', () {
    String? line(ServiceQueueItem item, {String? who = 'Anna'}) =>
        requestLine(item, _request(who: who), now: _now);

    test('who asked and when it should be ready', () {
      // Forty minutes from 20:00.
      expect(
        line(_item(etaSeconds: 40 * 60)),
        "Anna's request\u00A0· ready around 20:40",
      );
      expect(
        line(_item(etaSeconds: 70 * 60)),
        "Anna's request\u00A0· ready around 21:10",
      );
    });

    test(
      'past midnight it says tomorrow, and later in the week the weekday',
      () {
        expect(
          line(_item(etaSeconds: 13 * 3600)),
          "Anna's request\u00A0· ready around tomorrow 09:00",
        );
        expect(
          line(_item(etaSeconds: 3 * 24 * 3600)),
          "Anna's request\u00A0· ready around Monday",
        );
      },
    );

    test('with no estimate, or none worth saying, who alone', () {
      expect(line(_item()), "Anna's request");
      expect(line(_item(etaSeconds: 0)), "Anna's request");
      expect(line(_item(etaSeconds: -5)), "Anna's request");
    });

    test('a download waiting its turn has no time to be ready', () {
      expect(line(_item(etaSeconds: 600, queued: true)), "Anna's request");
    });

    test('a request that names nobody says nothing', () {
      expect(line(_item(etaSeconds: 600), who: null), isNull);
      expect(line(_item(etaSeconds: 600), who: '   '), isNull);
    });

    test('the name is trimmed', () {
      expect(line(_item(), who: '  Luca '), "Luca's request");
    });
  });
}

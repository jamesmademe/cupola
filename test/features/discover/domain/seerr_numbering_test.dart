import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

import '../../../test_helpers/fake_api_client.dart';

/// Seerr and Overseerr agree on the media codes up to 5 and part on 6:
/// Overseerr's DELETED is Seerr's BLOCKLISTED, and Seerr's DELETED is 7.
/// `server/constants/media.ts` in `sct/overseerr` and `seerr-team/seerr`.
void main() {
  group('the numbering a version names', () {
    test('Overseerr is 1.x', () {
      for (final version in ['1.33.2', '1.34.0', 'v1.33.2', ' 1.0.0 ']) {
        expect(
          SeerrNumbering.fromVersion(version),
          SeerrNumbering.overseerr,
          reason: version,
        );
      }
    });

    test('anything else is Seerr, develop builds included', () {
      for (final version in [
        '2.7.3', // Jellyseerr
        '3.0.0', // Seerr
        'v2.1.0',
        'develop-4f2a9c1',
        'develop',
        'preview-blocklist',
        '10.1.0',
      ]) {
        expect(
          SeerrNumbering.fromVersion(version),
          SeerrNumbering.seerr,
          reason: version,
        );
      }
    });

    test('no version says nothing', () {
      expect(SeerrNumbering.fromVersion(null), isNull);
      expect(SeerrNumbering.fromVersion(''), isNull);
      expect(SeerrNumbering.fromVersion('  '), isNull);
    });
  });

  group('one decoder for every surface', () {
    test('the shared codes read the same in both', () {
      for (final numbering in [...SeerrNumbering.values, null]) {
        expect(
          [
            for (var code = 1; code <= 5; code++)
              SeerrMediaAvailability.fromCode(code, numbering: numbering),
          ],
          [
            SeerrMediaAvailability.unknown,
            SeerrMediaAvailability.pending,
            SeerrMediaAvailability.processing,
            SeerrMediaAvailability.partiallyAvailable,
            SeerrMediaAvailability.available,
          ],
          reason: '$numbering',
        );
      }
    });

    test('Seerr: 6 blocklisted, 7 deleted', () {
      expect(
        SeerrMediaAvailability.fromCode(6, numbering: SeerrNumbering.seerr),
        SeerrMediaAvailability.blocklisted,
      );
      expect(
        SeerrMediaAvailability.fromCode('7', numbering: SeerrNumbering.seerr),
        SeerrMediaAvailability.deleted,
      );
    });

    test('Overseerr: 6 deleted', () {
      expect(
        SeerrMediaAvailability.fromCode(6, numbering: SeerrNumbering.overseerr),
        SeerrMediaAvailability.deleted,
      );
    });

    test('unread: 6 is neither guess, 7 is deleted', () {
      expect(
        SeerrMediaAvailability.fromCode(6, numbering: null),
        SeerrMediaAvailability.unknown,
      );
      expect(
        SeerrMediaAvailability.fromCode(7, numbering: null),
        SeerrMediaAvailability.deleted,
      );
    });

    test('a request row decodes its media in its server\'s numbering', () {
      final json = {
        'id': 1,
        'status': 2,
        'type': 'movie',
        'media': {'id': 9, 'tmdbId': 99, 'status': 6},
      };

      final seerr = SeerrRequest.fromJson(
        json,
        numbering: SeerrNumbering.seerr,
      );
      expect(seerr.displayStatus.label, 'Blocklisted');
      expect(seerr.displayStatus.kind, SeerrRequestDisplayKind.blocklisted);

      final overseerr = SeerrRequest.fromJson(
        json,
        numbering: SeerrNumbering.overseerr,
      );
      expect(overseerr.displayStatus.label, 'Deleted');
      expect(overseerr.displayStatus.kind, SeerrRequestDisplayKind.deleted);
    });
  });

  group('the service reads its numbering from /api/v1/status', () {
    test('once per connection, then keeps it', () async {
      final client = FakeApiClient()..getResponseData = {'version': '1.33.2'};
      final service = SeerrService(client);

      expect(await service.numbering(), SeerrNumbering.overseerr);
      expect(client.lastGetPath, '/api/v1/status');
      expect(await service.numbering(), SeerrNumbering.overseerr);
      expect(client.getCallCount, 1);
    });

    test('a develop build reads as Seerr', () async {
      final client = FakeApiClient()
        ..getResponseData = {'version': 'develop-4f2a9c1'};

      expect(await SeerrService(client).numbering(), SeerrNumbering.seerr);
    });

    test('a server that did not answer is asked again next time', () async {
      final client = FakeApiClient()..getException = Exception('down');
      final service = SeerrService(client);

      expect(await service.numbering(), isNull);

      client
        ..getException = null
        ..getResponseData = {'version': '2.7.3'};
      expect(await service.numbering(), SeerrNumbering.seerr);
      expect(client.getCallCount, 2);
    });

    test(
      'a request list is decoded in the numbering the server named',
      () async {
        final client = FakeApiClient();
        client.getResponseQueue.addAll([
          {'version': '1.33.2'},
          {
            'pageInfo': {'results': 1},
            'results': [
              {
                'id': 1,
                'status': 2,
                'type': 'movie',
                'media': {
                  'id': 9,
                  'tmdbId': 99,
                  'status': 6,
                  'title': 'Glass Half',
                  'posterPath': '/p.jpg',
                },
              },
            ],
          },
        ]);

        final requests = await SeerrService(client).getRequests();

        // Overseerr's 6: deleted, not barred.
        expect(requests.single.media!.status, SeerrMediaAvailability.deleted);
      },
    );
  });
}

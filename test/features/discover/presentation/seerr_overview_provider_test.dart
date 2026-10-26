import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_provider.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show askedAgo;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16, 12);

  group('seerrRequestHeadline', () {
    test('a movie is its title', () {
      expect(
        seerrRequestHeadline(_request(id: 1, title: 'Sinners')),
        'Sinners',
      );
    });

    test('one season is named, several are counted', () {
      expect(
        seerrRequestHeadline(
          _request(id: 2, title: 'Severance', type: 'tv', seasons: [2]),
        ),
        'Severance, Season 2',
      );
      expect(
        seerrRequestHeadline(
          _request(id: 3, title: 'The Bear', type: 'tv', seasons: [2, 3, 4]),
        ),
        'The Bear, 3 seasons',
      );
    });

    test('a request whose media carried no title still has a name', () {
      expect(
        seerrRequestHeadline(_request(id: 4, title: null)),
        'Untitled request',
      );
    });
  });

  group('seerrRequestDetail', () {
    test('names the requester, the age, the kind and the quality', () {
      expect(
        seerrRequestDetail(
          _request(
            id: 1,
            title: 'Dune: Part Three',
            requester: 'marco',
            createdAt: now.subtract(const Duration(hours: 4)).toIso8601String(),
            is4k: true,
          ),
          now: now,
        ),
        'marco\u00A0· 4\u00A0h ago\u00A0· Movie\u00A0· 4K',
      );
    });

    test('prints no quality clause when Seerr sent neither profile nor 4k', () {
      final detail = seerrRequestDetail(
        _request(id: 1, title: 'Sinners', requester: 'lea', createdAt: ''),
        now: now,
      );
      // No invented "1080p", and no age for a request with no readable date.
      expect(detail, 'lea\u00A0· Movie');
    });

    test('the age crosses its boundary at the hour, not near it', () {
      String age(Duration ago) => seerrRequestDetail(
        _request(
          id: 1,
          title: 'X',
          createdAt: now.subtract(ago).toIso8601String(),
        ),
        now: now,
      );

      expect(age(const Duration(minutes: 59)), '59\u00A0min ago\u00A0· Movie');
      expect(age(const Duration(minutes: 60)), '1\u00A0h ago\u00A0· Movie');
    });
  });

  group('seerrRequestDetail, past a week', () {
    // Local times, so the day each says is the day the test names.
    final today = DateTime(2026, 9, 16, 12);
    String when(DateTime asked) => seerrRequestDetail(
      _request(id: 1, title: 'X', createdAt: asked.toIso8601String()),
      now: today,
    );

    test('says the day as the app says dates, never the sortable one', () {
      expect(when(DateTime(2026, 9, 6, 12)), 'Sun 6 Sep\u00A0· Movie');
      expect(when(DateTime(2026, 9, 6, 12)), isNot(contains('2026-09-06')));
    });

    test('adds the year only when it is another one', () {
      expect(when(DateTime(2025, 12, 24, 12)), 'Wed 24 Dec 2025\u00A0· Movie');
    });

    test('names the weekday within the week, and dates from the seventh '
        'day', () {
      expect(when(DateTime(2026, 9, 15, 9)), 'yesterday\u00A0· Movie');
      expect(when(DateTime(2026, 9, 10, 12)), 'Thursday\u00A0· Movie');
      expect(when(DateTime(2026, 9, 9, 12)), 'Wed 9 Sep\u00A0· Movie');
    });

    test('reads the same as the same request does on the Home', () {
      for (final asked in [
        DateTime(2026, 9, 16, 11, 30),
        DateTime(2026, 9, 16, 1),
        DateTime(2026, 9, 15, 23),
        DateTime(2026, 9, 14, 9),
        DateTime(2026, 9, 10, 12),
        DateTime(2026, 9, 6, 12),
        DateTime(2025, 12, 24, 12),
      ]) {
        expect(when(asked), '${askedAgo(asked, now: today)}\u00A0· Movie');
      }
    });
  });

  group('seerrProcessingSection', () {
    test('keeps approved and processing, drops everything settled', () {
      final section = seerrProcessingSection([
        _request(id: 1, title: 'Approved', status: RequestStatus.approved),
        _request(
          id: 2,
          title: 'Processing',
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.processing,
        ),
        _request(
          id: 3,
          title: 'Available',
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.available,
        ),
        _request(id: 4, title: 'Waiting'),
        _request(id: 5, title: 'Declined', status: RequestStatus.declined),
      ], now: now);

      expect(section.total, 2);
      expect(
        section.rows.map((row) => row.headline),
        containsAll(<String>['Approved', 'Processing']),
      );
    });

    test('work in flight is informational, never a fault', () {
      final section = seerrProcessingSection([
        _request(id: 1, title: 'Andor', status: RequestStatus.approved),
      ], now: now);

      expect(section.rows.single.tone, StatusTone.info);
    });

    test('the total is counted before the preview is cut', () {
      final section = seerrProcessingSection(
        [
          for (var id = 1; id <= 9; id++)
            _request(id: id, title: 'R$id', status: RequestStatus.approved),
        ],
        now: now,
        limit: 3,
      );

      expect(section.rows, hasLength(3));
      expect(section.total, 9);
      expect(section.isFloor, isFalse);
    });

    test('a lost page of requests leaves the total a floor', () {
      final section = seerrProcessingSection(
        SeerrRequestList(
          [_request(id: 1, title: 'Andor', status: RequestStatus.approved)],
          total: 80,
          isPartial: true,
        ),
        now: now,
      );

      expect(section.total, 1);
      expect(section.isFloor, isTrue);
    });

    test('newest first, and an undated request sorts last', () {
      final section = seerrProcessingSection([
        _request(
          id: 1,
          title: 'Undated',
          status: RequestStatus.approved,
          createdAt: '',
        ),
        _request(
          id: 2,
          title: 'Older',
          status: RequestStatus.approved,
          createdAt: now.subtract(const Duration(days: 2)).toIso8601String(),
        ),
        _request(
          id: 3,
          title: 'Newer',
          status: RequestStatus.approved,
          createdAt: now.subtract(const Duration(hours: 1)).toIso8601String(),
        ),
      ], now: now);

      expect(section.rows.map((row) => row.headline), [
        'Newer',
        'Older',
        'Undated',
      ]);
    });
  });

  group('seerrDecisionRows', () {
    test('a pending request is NEUTRAL on a service home', () {
      // Amber is the Activity vocabulary, where a pending request is the thing
      // the page exists to surface. On a home a queue of approvals is the
      // normal resting state of a Seerr with no auto-approve rule.
      final rows = seerrDecisionRows([_request(id: 1, title: 'X')], now: now);
      expect(rows.single.tone, StatusTone.neutral);
    });
  });

  group('seerrOverviewDecisionsProvider', () {
    test(
      'keeps a waiting request whose media the library already holds',
      () async {
        // The displayStatus trap, inherited from `seerrDecisionsProvider`:
        // media availability overrides the request's own state, so this one
        // reads "Available" while still waiting on a person.
        final pendingButAvailable = _request(
          id: 1,
          title: 'Poor Things',
          mediaStatus: SeerrMediaAvailability.available,
        );
        expect(pendingButAvailable.displayStatus.label, 'Available');

        final container = ProviderContainer(
          overrides: [
            requestRowsProvider.overrideWith(
              (ref) async => [pendingButAvailable],
            ),
            seerrServiceProvider.overrideWithValue(FakeSeerrService()),
            // The operator's key: the rows he has always read.
            currentSettingsProvider.overrideWith(
              (ref) => settingsWithServices(const [ServiceKey.seerr]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final section = await container.read(
          seerrOverviewDecisionsProvider.future,
        );
        expect(section.total, 1);
        expect(section.rows.single.headline, 'Poor Things');
      },
    );
  });

  group('seerrOverviewProcessingProvider', () {
    test(
      'counts every row it works on, names only the five it draws',
      () async {
        final seerr = _NamingSeerr();
        final container = ProviderContainer(
          overrides: [
            requestRowsProvider.overrideWith(
              (ref) async => [
                for (var id = 1; id <= 12; id++)
                  _request(
                    id: id,
                    title: null,
                    status: RequestStatus.approved,
                    createdAt: '2026-09-${id.toString().padLeft(2, '0')}',
                  ),
              ],
            ),
            seerrServiceProvider.overrideWithValue(seerr),
            currentSettingsProvider.overrideWith(
              (ref) => settingsWithServices(const [ServiceKey.seerr]),
            ),
          ],
        );
        addTearDown(container.dispose);

        final section = await container.read(
          seerrOverviewProcessingProvider.future,
        );

        expect(section.total, 12);
        expect(section.rows, hasLength(seerrProcessingPreviewLimit));
        expect(seerr.hydrated, [12, 11, 10, 9, 8]);
      },
    );
  });
}

/// Remembers which rows it was asked to name.
class _NamingSeerr extends FakeSeerrService {
  final List<int> hydrated = [];

  @override
  Future<List<SeerrRequest>> hydrate(List<SeerrRequest> requests) async {
    hydrated.addAll(requests.map((r) => r.id));
    return requests;
  }
}

SeerrRequest _request({
  required int id,
  String? title = 'Title',
  RequestStatus status = RequestStatus.pendingApproval,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
  String createdAt = '2026-09-01T00:00:00Z',
  String type = 'movie',
  String? requester,
  bool is4k = false,
  List<int>? seasons,
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: title, tmdbId: id, status: mediaStatus),
  createdAt: createdAt,
  type: type,
  is4k: is4k,
  requestedBy: requester == null
      ? null
      : RequestedBy(id: id, displayName: requester),
  seasons: seasons
      ?.map((n) => RequestSeason(seasonNumber: n, status: 'pending'))
      .toList(),
);

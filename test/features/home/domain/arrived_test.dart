import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/home/domain/arrived.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final _now = DateTime(2026, 10, 8, 20, 40);
final _since = _now.subtract(const Duration(days: 7));

ArrHistoryEntry _import(
  String title, {
  ServiceKey service = ServiceKey.radarr,
  required Duration ago,
  int? tmdbId,
  int mediaId = 1,
  int? unitId,
  String instanceId = 'radarr-hd',
  String? connectionName,
  Duration? addedAgo,
}) => ArrHistoryEntry(
  service: service,
  id: title.hashCode,
  mediaId: mediaId,
  title: title,
  unitId: unitId,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(ago),
  reason: null,
  instanceId: instanceId,
  connectionName: connectionName,
  tmdbId: tmdbId,
  mediaAddedAt: addedAgo == null ? null : _now.subtract(addedAgo),
);

/// The words of the Home's Arrived.
void main() {
  group('the cards', () {
    test('one per title, the newest first, inside the week', () {
      final cards = arrivedOf([
        _import('Sintel', ago: const Duration(days: 3), tmdbId: 45745),
        _import('Spring', ago: const Duration(hours: 2), tmdbId: 1),
        _import('Old', ago: const Duration(days: 8), tmdbId: 2),
      ], since: _since);
      expect(cards.map((card) => card.title), ['Spring', 'Sintel']);
    });

    test('the HD and the 4K copy of one movie are one card, the newer', () {
      final cards = arrivedOf([
        _import('Tears of Steel', ago: const Duration(days: 1), tmdbId: 133701),
        _import(
          'Tears of Steel',
          ago: const Duration(hours: 5),
          tmdbId: 133701,
          instanceId: 'radarr-4k',
          connectionName: '4K',
        ),
      ], since: _since);
      expect(cards, hasLength(1));
      expect(cards.single.instanceId, 'radarr-4k');
    });

    test('a series arrives when it is new to the library, not with every '
        'episode of one that was there', () {
      final cards = arrivedOf([
        // Added on Sunday: new, one card for its three episodes.
        for (final hours in [3, 4, 5])
          _import(
            'Cosmos Laundromat',
            service: ServiceKey.sonarr,
            ago: Duration(hours: hours),
            tmdbId: 9001,
            addedAgo: const Duration(days: 3),
          ),
        // In the library for a month: its new episode is Coming up's news.
        _import(
          'Carrie',
          service: ServiceKey.sonarr,
          ago: const Duration(hours: 1),
          tmdbId: 9002,
          addedAgo: const Duration(days: 30),
        ),
        // Says nothing of when it was added: kept, not hidden.
        _import(
          'Cupertino',
          service: ServiceKey.sonarr,
          ago: const Duration(hours: 6),
          tmdbId: 9003,
        ),
      ], since: _since);
      expect(cards.map((card) => card.title), [
        'Cosmos Laundromat',
        'Cupertino',
      ]);
    });

    test('an album is one card, whatever its tracks', () {
      final cards = arrivedOf([
        for (final hours in [1, 2])
          _import(
            'Sintel (Anniversary Edition)',
            service: ServiceKey.lidarr,
            ago: Duration(hours: hours),
            unitId: 12,
            instanceId: 'lidarr',
          ),
      ], since: _since);
      expect(cards, hasLength(1));
    });
  });

  group('the line under the name', () {
    test('how many arrived in the last seven days', () {
      expect(
        arrivedSubtitle(4, SourceCoverage.answeredBy(ServiceKey.radarr)),
        'Last 7 days · 4 new',
      );
    });

    test('with a library silent, who the count is from', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, instanceId: 'radarr-hd'),
        SourceCoverage.answeredBy(ServiceKey.sonarr),
        SourceCoverage.failure(
          ServiceKey.radarr,
          const ClassifiedFailure(ServiceFailureReason.unreachable),
          instanceId: 'radarr-4k',
          name: '4K',
        ),
      ]);
      expect(
        arrivedSubtitle(2, coverage),
        'Last 7 days · 2 from Radarr and Sonarr',
      );
    });
  });

  test('a card says when, and which connection while there are two', () {
    expect(
      arrivedCardLine(
        _import('Spring', ago: Duration.zero, connectionName: '4K'),
        when: '2 h ago',
      ),
      '2 h ago · Radarr 4K',
    );
    expect(
      arrivedCardLine(_import('Sintel', ago: Duration.zero), when: 'Sunday'),
      'Sunday',
    );
  });
}

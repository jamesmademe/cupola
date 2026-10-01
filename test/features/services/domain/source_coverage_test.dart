import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  const silent = SocketException('Connection refused');
  const refused = ClassifiedFailure(ServiceFailureReason.unauthorized);

  group('merge', () {
    test('a service is answered only when every read of it answered', () {
      final merged = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        SourceCoverage.answeredBy(ServiceKey.lidarr),
        SourceCoverage.failure(ServiceKey.lidarr, silent),
        SourceCoverage.answeredBy(ServiceKey.sonarr),
        SourceCoverage.pendingOf([ServiceKey.sonarr, ServiceKey.dockge]),
      ]);

      expect(merged.answered, {ServiceKey.radarr});
      expect(merged.failed, {
        ServiceKey.lidarr: ServiceFailureReason.unreachable,
      });
      expect(merged.pending, {ServiceKey.sonarr, ServiceKey.dockge});
    });

    test('nothing configured is whole, and is not a failure', () {
      final merged = SourceCoverage.merge([
        SourceCoverage.none,
        SourceCoverage.none,
      ]);
      expect(merged.isWhole, isTrue);
      expect(merged.everySourceFailed, isFalse);
    });
  });

  group('the figure', () {
    test('every source failed reads an em dash, never 0', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.failure(ServiceKey.qbittorrent, refused),
      ]);
      expect(coveredFigure(0, coverage), '—');
    });

    test('a source still out is not a failure yet', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.pendingOf([ServiceKey.sonarr]),
      ]);
      expect(coverage.everySourceFailed, isFalse);
      expect(coveredFigure(0, coverage), '0');
    });

    test('a dash is spoken as a missing count', () {
      expect(
        spokenCountPhrase('— downloading'),
        'downloading, count unavailable',
      );
      expect(spokenCountPhrase('3 downloading'), '3 downloading');
    });

    test('a source that answered with part of itself makes the figure a '
        'floor, with nobody to name', () {
      // Radarr's queue walk stopped on a full page with no total: its rows
      // are what arrived, not the queue.
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
        SourceCoverage.answeredBy(ServiceKey.qbittorrent),
      ]);

      expect(coverage.isFloor, isTrue);
      expect(coverage.isWhole, isFalse);
      expect(coveredFigure(200, coverage), '200+');
      expect(coverageNote(coverage), isNull);
    });

    test('a source that failed is not a floor of itself', () {
      // Answered short in one read and failed in another: the failure wins,
      // and the source is named under the figure instead.
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.answeredBy(ServiceKey.sonarr),
      ]);

      expect(coverage.cutShort, isEmpty);
      expect(coverage.isFloor, isFalse);
      expect(coveredFigure(3, coverage), '3');
    });

    test('a floor is spoken as the least there is', () {
      expect(
        spokenCountPhrase('200+ downloading, 2.0 MB/s across 1 client'),
        'at least 200 downloading, 2.0 MB/s across 1 client',
      );
      expect(spokenCountPhrase('3+'), 'at least 3');
    });
  });

  group('the note under a partial total', () {
    test('names what is missing, silence first, and no reasons', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        SourceCoverage.failure(ServiceKey.qbittorrent, refused),
        SourceCoverage.failure(ServiceKey.sabnzbd, silent),
        SourceCoverage.failure(ServiceKey.lidarr, silent),
      ]);

      expect(
        coverageNote(coverage),
        'Not in the total: Lidarr, SABnzbd, qBittorrent',
      );
      expect(coverage.anyDidNotAnswer, isTrue);
    });

    test('counts past two names', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        for (final service in const [
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.prowlarr,
          ServiceKey.dockge,
        ])
          SourceCoverage.failure(service, silent),
      ]);

      expect(
        coverageNote(coverage),
        'Not in the total: Sonarr, Lidarr and 2 others',
      );
    });

    test('the cap is per kind of failure, as it always was', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        for (final service in const [
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.prowlarr,
        ])
          SourceCoverage.failure(service, silent),
        SourceCoverage.failure(ServiceKey.qbittorrent, refused),
      ]);

      expect(
        coverageNote(coverage),
        'Not in the total: Sonarr, Lidarr, qBittorrent and 1 other',
      );
    });

    test('is absent when the total is whole, or when there is no total', () {
      expect(
        coverageNote(SourceCoverage.answeredBy(ServiceKey.radarr)),
        isNull,
      );
      expect(
        coverageNote(SourceCoverage.failure(ServiceKey.radarr, silent)),
        isNull,
      );
    });

    test('a refusal alone is amber', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        SourceCoverage.failure(ServiceKey.sonarr, refused),
      ]);
      expect(coverage.anyDidNotAnswer, isFalse);
      expect(coverageNote(coverage), 'Not in the total: Sonarr');
    });
  });

  test('every source failed says each in its own words', () {
    final coverage = SourceCoverage.merge([
      SourceCoverage.failure(ServiceKey.radarr, silent),
      SourceCoverage.failure(ServiceKey.sonarr, silent),
      SourceCoverage.failure(ServiceKey.qbittorrent, refused),
    ]);

    expect(
      coverageFailureSentence(coverage),
      'Radarr and Sonarr did not answer. qBittorrent answered but refused '
      'the sign-in.',
    );
  });
}

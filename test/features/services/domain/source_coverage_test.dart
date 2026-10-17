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

      expect(merged.answered, {const CoverageSource(ServiceKey.radarr)});
      expect(merged.failed, {
        const CoverageSource(ServiceKey.lidarr):
            ServiceFailureReason.unreachable,
      });
      expect(merged.pending, {
        const CoverageSource(ServiceKey.sonarr),
        const CoverageSource(ServiceKey.dockge),
      });
    });

    test('two connections of one service each keep their own answer', () {
      // The 4K Radarr did not answer. The HD one did, and its share of the
      // figure stands: keyed on the service alone, the 4K's silence took the
      // HD's answer out with it and a Radarr-only region read a dash.
      final merged = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, instanceId: 'radarr'),
        SourceCoverage.failure(
          ServiceKey.radarr,
          silent,
          instanceId: 'radarr-4k',
          name: '4K',
        ),
      ]);

      expect(merged.everySourceFailed, isFalse);
      expect(merged.isPartial, isTrue);
      expect(coveredFigure(3, merged), '3');
      expect(coverageNote(merged), 'Not in the total: Radarr 4K');
      expect(merged.failedServices, {ServiceKey.radarr});
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
        spokenCountPhrase('200+ downloading, 2.0 MB/\u2060s across 1 client'),
        'at least 200 downloading, 2.0 MB/\u2060s across 1 client',
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

  group('equal faults are grouped', () {
    const slow = ClassifiedFailure(ServiceFailureReason.timeout);

    test('in one sentence, named as the silent ones are', () {
      // Eight services behind one stuck host: the lab paused, 13/10.
      final coverage = SourceCoverage.merge([
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.readarr,
          ServiceKey.qbittorrent,
          ServiceKey.transmission,
          ServiceKey.sabnzbd,
          ServiceKey.nzbget,
        ])
          SourceCoverage.failure(service, slow),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Radarr, Sonarr and 6 others were reached but did not reply in time.',
      );
    });

    test('two of a kind are both named', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.jellyfin, slow),
        SourceCoverage.failure(ServiceKey.plex, slow),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Jellyfin and Plex were reached but did not reply in time.',
      );
    });

    test('silence first, then each kind of fault once', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, refused),
        SourceCoverage.failure(ServiceKey.sonarr, slow),
        SourceCoverage.failure(ServiceKey.lidarr, refused),
        SourceCoverage.failure(ServiceKey.readarr, silent),
        SourceCoverage.failure(ServiceKey.prowlarr, slow),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Readarr did not answer. Radarr and Lidarr answered but refused their '
        'keys. Sonarr and Prowlarr were reached but did not reply in time.',
      );
    });

    test('a key and a sign-in refused are two sentences', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, refused),
        SourceCoverage.failure(ServiceKey.qbittorrent, refused),
        SourceCoverage.failure(ServiceKey.transmission, refused),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Radarr answered but refused the key. qBittorrent and Transmission '
        'answered but refused the sign-in.',
      );
    });

    test('a fault that cannot be said of many says each', () {
      const gateway = ClassifiedFailure(ServiceFailureReason.accessGateway);
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, gateway),
        SourceCoverage.failure(ServiceKey.sonarr, gateway),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Something in front of Radarr answered instead of it. Something in '
        'front of Sonarr answered instead of it.',
      );
    });
  });
}

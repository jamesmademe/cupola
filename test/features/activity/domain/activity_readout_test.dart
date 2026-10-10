/// The words under Activity's title: what moves, how fast, what is stuck, or
/// when the last download finished.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart'
    show ServiceFailureReason;
import 'package:cupola/core/status/media_status.dart' show StatusTone;

import 'package:cupola/features/activity/domain/activity_readout.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _mb = 1024 * 1024;

/// Friday 9 October 2026, 20:00, on this device's clock.
final _now = DateTime(2026, 10, 9, 20);

/// The parts as the page reads them, figure and words.
List<String> _words(List<ActivityReadoutPart> parts) => [
  for (final part in parts) '${part.figure} ${part.words}',
];

void main() {
  group('activityReadoutParts', () {
    test('nothing moving and nothing stuck has no parts: the page says '
        'Nothing moving', () {
      expect(activityReadoutParts(moving: 0, stuck: 0), isEmpty);
      // Not even a measured speed makes a readout of nothing.
      expect(
        activityReadoutParts(moving: 0, stuck: 0, rateBytesPerSecond: 5 * _mb),
        isEmpty,
      );
      expect(nothingMoving, 'Nothing moving');
    });

    test('what moves, how fast, and what is stuck, in that order', () {
      final parts = activityReadoutParts(
        moving: 4,
        stuck: 1,
        rateBytesPerSecond: (40.4 * _mb).round(),
      );

      expect(_words(parts), ['4 moving', '40.4 MB/s', '1 stuck']);
      expect([for (final part in parts) part.stuck], [false, false, true]);
    });

    test('the speed splits at the no-break space its formatter puts between '
        'figure and unit, and never drops', () {
      // formatBytesPerSecond joins them with U+00A0: a split on a plain
      // space once lost the speed on every machine that measured one.
      for (final (rate, figure, unit) in [
        (512, '512', 'B/s'),
        (300 * 1024, '300', 'KB/s'),
        ((4.2 * _mb).round(), '4.2', 'MB/s'),
        (3 * 1024 * _mb, '3.0', 'GB/s'),
      ]) {
        final parts = activityReadoutParts(
          moving: 1,
          stuck: 0,
          rateBytesPerSecond: rate,
        );
        expect(_words(parts), ['1 moving', '$figure $unit'], reason: '$rate');
      }
    });

    test('no speed when no client measured one, or when nothing moves', () {
      expect(_words(activityReadoutParts(moving: 3, stuck: 0)), ['3 moving']);
      // Stuck alone: a rate over nothing that moves is not the speed of
      // anything on the page.
      expect(
        _words(
          activityReadoutParts(
            moving: 0,
            stuck: 2,
            rateBytesPerSecond: 5 * _mb,
          ),
        ),
        ['2 stuck'],
      );
    });

    test('stuck alone, and moving alone', () {
      expect(_words(activityReadoutParts(moving: 0, stuck: 1)), ['1 stuck']);
      expect(activityReadoutParts(moving: 0, stuck: 1).single.stuck, isTrue);
      expect(activityReadoutParts(moving: 2, stuck: 0).single.stuck, isFalse);
    });

    test('a walk cut short makes the counts floors, the speed untouched', () {
      final coverage = SourceCoverage.answeredBy(
        ServiceKey.radarr,
        cutShort: true,
      );

      expect(
        _words(
          activityReadoutParts(
            moving: 20,
            stuck: 3,
            rateBytesPerSecond: 2 * _mb,
            coverage: coverage,
          ),
        ),
        ['20+ moving', '2.0 MB/s', '3+ stuck'],
      );
    });

    test('with no source answering a count is a dash, never a zero', () {
      final coverage = SourceCoverage.failure(
        ServiceKey.radarr,
        Exception('down'),
      );

      expect(
        _words(activityReadoutParts(moving: 1, stuck: 1, coverage: coverage)),
        ['— moving', '— stuck'],
      );
    });

    test('nothing counted because nobody answered is a dash, not Nothing '
        'moving', () {
      final everyone = SourceCoverage.failure(
        ServiceKey.radarr,
        Exception('down'),
      );

      expect(
        _words(activityReadoutParts(moving: 0, stuck: 0, coverage: everyone)),
        ['— moving'],
      );
      expect(
        spokenActivityReadout(
          activityReadoutParts(moving: 0, stuck: 0, coverage: everyone),
        ),
        'moving, count unavailable',
      );
      // Some answering is an answer: the empty queue is nothing moving, and
      // the failed one is named under the title.
      final some = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.sonarr),
        everyone,
      ]);
      expect(
        activityReadoutParts(moving: 0, stuck: 0, coverage: some),
        isEmpty,
      );
    });

    test('a part reads, compares and prints as its words', () {
      const part = ActivityReadoutPart('4', 'moving');
      expect(part.toString(), '4 moving');
      expect(part, const ActivityReadoutPart('4', 'moving'));
      expect(part.hashCode, const ActivityReadoutPart('4', 'moving').hashCode);
      expect(
        part,
        isNot(const ActivityReadoutPart('4', 'moving', stuck: true)),
      );
      expect(part, isNot(const ActivityReadoutPart('5', 'moving')));
      expect(part, isNot(const ActivityReadoutPart('4', 'stuck')));
    });
  });

  group('spokenActivityReadout', () {
    test('the speed says its unit in words, the rest as they read', () {
      final parts = activityReadoutParts(
        moving: 4,
        stuck: 1,
        rateBytesPerSecond: (40.4 * _mb).round(),
      );

      expect(
        spokenActivityReadout(parts),
        '4 moving, 40.4 megabytes a second, 1 stuck',
      );
    });

    test('a floor says at least, a dash says the count is unavailable', () {
      final floor = SourceCoverage.answeredBy(
        ServiceKey.radarr,
        cutShort: true,
      );
      expect(
        spokenActivityReadout(
          activityReadoutParts(moving: 20, stuck: 3, coverage: floor),
        ),
        'at least 20 moving, at least 3 stuck',
      );

      final dark = SourceCoverage.failure(ServiceKey.radarr, Exception('x'));
      expect(
        spokenActivityReadout(
          activityReadoutParts(moving: 1, stuck: 1, coverage: dark),
        ),
        'moving, count unavailable, stuck, count unavailable',
      );
    });

    test('each unit has its words', () {
      for (final (rate, spoken) in [
        (512, '512 bytes a second'),
        (300 * 1024, '300 kilobytes a second'),
        (2 * _mb, '2.0 megabytes a second'),
      ]) {
        expect(
          spokenActivityReadout(
            activityReadoutParts(moving: 1, stuck: 0, rateBytesPerSecond: rate),
          ),
          '1 moving, $spoken',
        );
      }
    });

    test('a part says itself as a phrase', () {
      expect(const ActivityReadoutPart('4', 'moving').spoken, '4 moving');
      expect(
        const ActivityReadoutPart('20+', 'moving').spoken,
        'at least 20 moving',
      );
    });
  });

  group('lastDownloadFinished', () {
    test('nothing says, nothing is said', () {
      expect(lastDownloadFinished(null, now: _now), isNull);
    });

    test('today the clock, yesterday the word and the clock', () {
      expect(
        lastDownloadFinished(DateTime(2026, 10, 9, 18, 52), now: _now),
        'Last download finished 18:52',
      );
      expect(
        lastDownloadFinished(DateTime(2026, 10, 9, 0, 5), now: _now),
        'Last download finished 00:05',
      );
      expect(
        lastDownloadFinished(DateTime(2026, 10, 8, 18, 52), now: _now),
        'Last download finished yesterday 18:52',
      );
    });

    test('two to six days ago the weekday, and a week or more nothing', () {
      for (final (day, weekday) in [
        (7, 'Wednesday'),
        (6, 'Tuesday'),
        (5, 'Monday'),
        (4, 'Sunday'),
        (3, 'Saturday'),
      ]) {
        expect(
          lastDownloadFinished(DateTime(2026, 10, day, 18, 52), now: _now),
          'Last download finished $weekday 18:52',
          reason: 'October $day',
        );
      }
      // Seven days is the week's edge, and past it the line is left out.
      expect(
        lastDownloadFinished(DateTime(2026, 10, 2, 18, 52), now: _now),
        isNull,
      );
      expect(
        lastDownloadFinished(DateTime(2026, 9, 1, 18, 52), now: _now),
        isNull,
      );
    });

    test('a time ahead of the clock says nothing rather than something '
        'false', () {
      expect(
        lastDownloadFinished(DateTime(2026, 10, 10, 8), now: _now),
        isNull,
      );
    });

    test('a moment in UTC reads on this device\'s clock', () {
      final utc = DateTime.utc(2026, 10, 9, 18, 52);
      final local = utc.toLocal();
      expect(
        lastDownloadFinished(utc, now: _now),
        'Last download finished '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
      );
    });
  });

  group("the window's answer line", () {
    const radarr = CoverageSource(ServiceKey.radarr, instanceId: 'radarr');
    const sonarr = CoverageSource(ServiceKey.sonarr, instanceId: 'sonarr');
    const seerr = CoverageSource(ServiceKey.seerr, instanceId: 'seerr');
    final at = DateTime(2026, 10, 9, 20, 53);

    test('every source answered: all of them, and when the last did', () {
      final line = activityAnswerLine(
        SourceCoverage(answered: {radarr, sonarr, seerr}),
        at: at,
      );
      expect(line?.text, 'All 3 answered at 20:53');
      expect(line?.tone, isNull);
    });

    test('the Needs you page names what it counted', () {
      expect(
        activityAnswerLine(
          SourceCoverage(answered: {radarr, sonarr}),
          at: at,
          services: true,
        )?.text,
        'All 2 services answered at 20:53',
      );
      expect(
        activityAnswerLine(
          SourceCoverage(answered: {radarr}),
          at: at,
          services: true,
        )?.text,
        'The one service answered at 20:53',
      );
    });

    test('with the slowest still out: how many did, no tone', () {
      final line = activityAnswerLine(
        SourceCoverage(answered: {radarr}, pending: {sonarr, seerr}),
        at: at,
      );
      expect(line?.text, '1 of 3 answered');
      expect(line?.tone, isNull);
    });

    test('before any answered, it is asking', () {
      expect(
        activityAnswerLine(SourceCoverage(pending: {radarr, sonarr}))?.text,
        'Asking 2',
      );
    });

    test('one that did not answer is red; one that refused, amber', () {
      final silent = activityAnswerLine(
        SourceCoverage(
          answered: {radarr, seerr},
          failed: {sonarr: ServiceFailureReason.unreachable},
        ),
        at: at,
      );
      expect(silent?.text, '2 of 3 answered');
      expect(silent?.tone, StatusTone.error);

      final refused = activityAnswerLine(
        SourceCoverage(
          answered: {radarr, seerr},
          failed: {sonarr: ServiceFailureReason.unauthorized},
        ),
        at: at,
      );
      expect(refused?.tone, StatusTone.warning);
    });

    test('nothing to ask says nothing', () {
      expect(activityAnswerLine(SourceCoverage.none), isNull);
    });
  });
}

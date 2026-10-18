/// What a multi-connection stack card is allowed to add up, and what it is not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';

ServiceKpi kpi(String label, String value, {StatusTone? tone, String? note}) =>
    ServiceKpi(
      label: label,
      value: value,
      icon: Icons.circle,
      tone: tone,
      note: note,
    );

void main() {
  group('what folds', () {
    test('a count is the sum of the connections', () {
      final folded = aggregateServiceKpis([
        [kpi('Movies', '900')],
        [kpi('Movies', '1138')],
      ]);

      expect(folded!.single.value, '2038');
    });

    test('a count of titles counts each title once', () {
      // An HD and a 4K Radarr holding the same films: the sum is a count of
      // copies, and the card would have stated it as a count of films.
      final folded = aggregateServiceKpis([
        [
          ServiceKpi(
            label: 'Movies',
            value: '3',
            icon: Icons.circle,
            members: const {101, 102, 103},
          ),
        ],
        [
          ServiceKpi(
            label: 'Movies',
            value: '2',
            icon: Icons.circle,
            members: const {102, 104},
          ),
        ],
      ]);

      expect(folded!.single.value, '4');
    });

    test('a floor in the sum makes the sum a floor', () {
      // One Readarr's queue walk stopped on a full page with no total. Left
      // unparsed, the fold fell through to the lens and printed its "200+" as
      // the fleet's figure, with the other connection's three left out.
      final folded = aggregateServiceKpis([
        [kpi('Queue', '200+')],
        [kpi('Queue', '3')],
      ]);

      expect(folded!.single.value, '203+');
    });

    test('a byte rate is the sum of the connections', () {
      // 2.0 MB/s + 512 KB/s is 2.5 MB/s, on the same binary ladder the cards
      // already print.
      final folded = aggregateServiceKpis([
        [kpi('Download', '2.0\u00A0MB/\u2060s')],
        [kpi('Download', '512\u00A0KB/\u2060s')],
      ]);

      expect(folded!.single.value, '2.5\u00A0MB/\u2060s');
    });

    test('a rate printed whole from 100 up still adds', () {
      // `120 MB/s` is how the ladder prints a rate from 100 up in a unit: no
      // decimal, so the parser must not insist on one.
      final folded = aggregateServiceKpis([
        [kpi('Download', '12.4\u00A0MB/\u2060s')],
        [kpi('Download', '120\u00A0MB/\u2060s')],
      ]);

      expect(folded!.single.value, '132\u00A0MB/\u2060s');
    });

    test('one connection folds to itself', () {
      final lens = [kpi('Movies', '900')];

      expect(aggregateServiceKpis([lens]), same(lens));
    });
  });

  group('what refuses to fold', () {
    test('a percentage keeps the lens: the mean describes no disk', () {
      final folded = aggregateServiceKpis([
        [kpi('Pool', '81%')],
        [kpi('Pool', '35%')],
      ]);

      expect(folded!.single.value, '81%');
    });

    test('a ratio keeps the lens', () {
      final folded = aggregateServiceKpis([
        [kpi('Episodes', '4/6')],
        [kpi('Episodes', '3/9')],
      ]);

      expect(folded!.single.value, '4/6');
    });

    test('a state word keeps the lens', () {
      final folded = aggregateServiceKpis([
        [kpi('Status', 'Paused')],
        [kpi('Status', 'Downloading')],
      ]);

      expect(folded!.single.value, 'Paused');
    });
  });

  group('the fold is never partial', () {
    test('a connection that could not be read takes the whole fold away', () {
      // A sum missing a term is worse than no sum: it looks like a sum.
      expect(
        aggregateServiceKpis([
          [kpi('Movies', '900')],
          null,
        ]),
        isNull,
      );
    });

    test('nothing to fold is not an empty fold', () {
      expect(aggregateServiceKpis([]), isNull);
    });

    test('a figure that did not answer reads as unavailable, not as a sum', () {
      final folded = aggregateServiceKpis([
        [kpi('Queue', '12')],
        [ServiceKpi.unavailable(label: 'Queue', icon: Icons.circle)],
      ]);

      expect(folded!.single.isUnavailable, isTrue);
      expect(folded.single.value, ServiceKpi.unavailableValue);
    });

    test('lists reporting different things do not fold by position', () {
      // Two connections of one service run one builder, so a mismatch means
      // one of them answered something else, and folding by position would
      // add a film count to a disk percentage.
      expect(
        aggregateServiceKpis([
          [kpi('Movies', '900')],
          [kpi('Pool', '35')],
        ]),
        isNull,
      );
      expect(
        aggregateServiceKpis([
          [kpi('Movies', '900'), kpi('Missing', '4')],
          [kpi('Movies', '900')],
        ]),
        isNull,
      );
    });
  });

  group('the judgement travels with the figure', () {
    test('a fault on one connection is a fault in the fold', () {
      final folded = aggregateServiceKpis([
        [kpi('Fails', '0')],
        [kpi('Fails', '3', tone: StatusTone.warning)],
      ]);

      expect(folded!.single.value, '3');
      expect(folded.single.tone, StatusTone.warning);
    });

    test('a backlog on one connection is backlog, not silence', () {
      final folded = aggregateServiceKpis([
        [kpi('Missing', '0')],
        [kpi('Missing', '34', tone: StatusTone.neutral)],
      ]);

      expect(folded!.single.tone, StatusTone.neutral);
    });

    test('two connections with two reasons have no single reason', () {
      final folded = aggregateServiceKpis([
        [kpi('Queue', '1', note: 'client not answering')],
        [kpi('Queue', '2', note: 'indexer unreachable')],
      ]);

      // Neither reason survives, so the sum cannot say why it is short: it
      // says that it is.
      expect(folded!.single.value, '3+');
      expect(folded.single.note, isNull);
    });

    test('a count that loses what qualified one term is a floor', () {
      // The server's API key counts everyone's playback; a household member's
      // token counts only her own. Their sum is at least 2, never 2.
      final folded = aggregateServiceKpis([
        [kpi('Streams', '1')],
        [kpi('Streams', '1', note: 'yours only')],
      ]);

      expect(folded!.single.value, '2+');
      expect(folded.single.note, isNull);
    });

    test('a union that loses what qualified one term is a floor too', () {
      final folded = aggregateServiceKpis([
        [
          const ServiceKpi(
            label: 'Movies',
            value: '2',
            icon: Icons.movie_rounded,
            members: {1, 2},
          ),
        ],
        [
          const ServiceKpi(
            label: 'Movies',
            value: '1',
            icon: Icons.movie_rounded,
            note: 'yours only',
            members: {2},
          ),
        ],
      ]);

      expect(folded!.single.value, '2+');
    });

    test('a qualifier every term shares is said, and the sum stands', () {
      final folded = aggregateServiceKpis([
        [kpi('Streams', '1', note: 'yours only')],
        [kpi('Streams', '2', note: 'yours only')],
      ]);

      expect(folded!.single.value, '3');
      expect(folded.single.note, 'yours only');
    });

    test('one reason, said by every connection, survives', () {
      final folded = aggregateServiceKpis([
        [kpi('Queue', '1', note: 'client not answering')],
        [kpi('Queue', '2', note: 'client not answering')],
      ]);

      expect(folded!.single.note, 'client not answering');
    });
  });

  group('a rail whose sample stopped', () {
    test('reads a dash for each rate, noted not updating', () {
      final rail = withRatesNotUpdating([
        kpi('Download', '22.4\u00A0MB/\u2060s', tone: StatusTone.info),
        kpi('Upload', '0\u00A0B/\u2060s'),
      ]);

      for (final figure in rail) {
        expect(figure.isUnavailable, isTrue, reason: figure.label);
        expect(figure.note, 'not updating');
        expect(figure.tone, isNull, reason: 'a stopped rate is not activity');
      }
      expect(rail.map((figure) => figure.label), ['Download', 'Upload']);
    });

    test('keeps every figure that is not a rate', () {
      final figures = [
        kpi('Active', '23'),
        kpi('Queue', '50+'),
        kpi('Stuck', '1', tone: StatusTone.warning),
        kpi('Ratio', '2.40'),
      ];

      expect(withRatesNotUpdating(figures), figures);
    });
  });
}

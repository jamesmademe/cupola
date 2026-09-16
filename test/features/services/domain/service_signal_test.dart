import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/services/domain/service_signal.dart';

ServiceKpi _kpi(String label, String value, {StatusTone? tone}) =>
    ServiceKpi(label: label, value: value, icon: Icons.circle, tone: tone);

void main() {
  group('resolveServiceSignal', () {
    test('returns null when a service reports no KPIs', () {
      expect(resolveServiceSignal(const []), isNull);
    });

    test('falls back to the headline metric when nothing is flagged', () {
      final signal = resolveServiceSignal([
        _kpi('Movies', '312'),
        _kpi('Monitored', '300'),
        _kpi('Missing', '0'),
      ]);

      expect(signal!.label, 'movies');
      expect(signal.value, '312');
      expect(signal.tone, StatusTone.neutral);
      expect(signal.needsAttention, isFalse);
    });

    test('prefers the first flagged KPI over the headline', () {
      // The KPI builders mark their own noteworthy metric with a non-null
      // tone — `_backlogIf(missing > 0)`. That flag is the domain's judgment
      // about its own data, so this reads it instead of restating a per-service
      // table here.
      final signal = resolveServiceSignal([
        _kpi('Movies', '312'),
        _kpi('Monitored', '300'),
        _kpi('Missing', '7', tone: StatusTone.neutral),
      ]);

      expect(signal!.label, 'missing');
      expect(signal.value, '7');
      // Selected, but not coloured: a backlog is why you would open Radarr and
      // is still not something asking for you.
      expect(signal.needsAttention, isFalse);
    });

    test('takes the earliest flag when several are raised', () {
      final signal = resolveServiceSignal([
        _kpi('Pools', '2'),
        _kpi('Used', '91%', tone: StatusTone.warning),
        _kpi('Alerts', '3', tone: StatusTone.warning),
      ]);

      expect(signal!.label, 'used');
    });

    group('tone', () {
      // The tone is no longer derived here from the KPI's label: the builder
      // that computed the number says which kind of fact it is, and this reads
      // it. These three tests are what stops the derivation coming back.
      test('an active transfer reads as activity, not as a fault', () {
        final signal = resolveServiceSignal([
          _kpi('Down', '2.4 MB/s', tone: StatusTone.info),
          _kpi('Queue', '3'),
        ]);

        expect(signal!.tone, StatusTone.info);
        expect(signal.needsAttention, isTrue);
      });

      test('a fault reads as amber, never as red', () {
        // An exited stack and a failing indexer were meant to be running and
        // are not. Red is not available to them: on a service cell red is
        // reachability, and a figure only exists because the service answered.
        for (final label in ['Exited', 'Fails']) {
          final signal = resolveServiceSignal([
            _kpi('Stacks', '9'),
            _kpi(label, '2', tone: StatusTone.warning),
          ]);
          expect(signal!.tone, StatusTone.warning, reason: label);
          expect(signal.tone, isNot(StatusTone.error), reason: label);
        }
      });

      test('backlog is surfaced without being coloured', () {
        // The case the old code got backwards. A Bazarr with 14 wanted
        // subtitles is still the headline — it is why you would open Bazarr —
        // but it is work to do, not a fault, so it carries no tone.
        final signal = resolveServiceSignal([
          _kpi('Wanted', '14', tone: StatusTone.neutral),
        ]);

        expect(signal!.label, 'wanted');
        expect(signal.value, '14');
        expect(signal.tone, StatusTone.neutral);
      });
    });

    test('spoken form puts the label before the figure', () {
      // The cell paints "2.4 MB/s incoming" because the eye scans a column of
      // figures. Read back in that order it is nonsense.
      final signal = resolveServiceSignal([
        _kpi('Down', '2.4 MB/s', tone: StatusTone.info),
      ]);

      expect(signal!.spoken, 'Incoming 2.4 MB/s');
    });

    group('the matrix vocabulary', () {
      test('a download rate never says "down" on a reachability grid', () {
        // The one word this screen cannot borrow: the cell's other possible live
        // line is literally "Offline", so "2.4 MB/s down" reads as a service that
        // is down rather than as bytes arriving.
        final signal = resolveServiceSignal([
          _kpi('Down', '2.4 MB/s', tone: StatusTone.info),
        ]);

        // And short enough to survive a 168pt cell: "downloading" ellipsised to
        // "downloa…" at the default reading size.
        expect(signal!.label, 'incoming');
      });

      test('a state word carries no label after it', () {
        // SABnzbd and NZBGet report their paused queue as `Status: Paused`, and
        // the cell paints value-then-label — so keeping the label printed
        // "Paused status".
        final signal = resolveServiceSignal([
          _kpi('Status', 'Paused', tone: StatusTone.neutral),
        ]);

        expect(signal!.label, isEmpty);
        expect(signal.spoken, 'Paused');
      });

      test("Prowlarr's truncation becomes a noun", () {
        final signal = resolveServiceSignal([
          _kpi('Fails', '3', tone: StatusTone.warning),
        ]);

        expect(signal!.label, 'failures');
      });

      test('a label agrees in number with its own figure', () {
        expect(
          resolveServiceSignal([
            _kpi('Alerts', '1', tone: StatusTone.warning),
          ])!.label,
          'alert',
        );
        expect(
          resolveServiceSignal([
            _kpi('Alerts', '4', tone: StatusTone.warning),
          ])!.label,
          'alerts',
        );
      });

      test('a figure that is not a count is left alone', () {
        // `85%`, `4/6` and `2.4 MB/s` all parse to null, which is correct: those
        // labels are not counts and must not be singularized by a stray "1".
        for (final value in ['85%', '4/6', '1.0 MB/s']) {
          expect(
            resolveServiceSignal([
              _kpi('Pools', value, tone: StatusTone.neutral),
            ])!.label,
            'pools',
            reason: value,
          );
        }
      });

      test('"series" reads the same for one and for many', () {
        expect(resolveServiceSignal([_kpi('Series', '1')])!.label, 'series');
        expect(resolveServiceSignal([_kpi('Series', '9')])!.label, 'series');
      });
    });
  });
}

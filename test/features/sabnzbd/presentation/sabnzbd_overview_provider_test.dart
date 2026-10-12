import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_provider.dart';

/// Every rule on the SABnzbd Overview is a top-level function taking an
/// explicit `now`, so every boundary below is exercised without a clock, a
/// container or a pump.
void main() {
  group('sabnzbdStatusTone: the five-arm rule on SABnzbd\'s own words', () {
    test('a paused job is neutral, never amber', () {
      // The single most common way the tone rule is broken. Pausing is the
      // user obeying nobody but themselves; amber would put it in the same
      // colour as a download that broke on its own.
      expect(sabnzbdStatusTone('Paused'), StatusTone.neutral);
      expect(sabnzbdStatusTone('Deleted'), StatusTone.neutral);
    });

    test('failed is the only fault', () {
      expect(sabnzbdStatusTone('Failed'), StatusTone.warning);
    });

    test('repairing is post-processing, not a fault', () {
      // par2 rebuilding broken articles is the recovery working: the same run
      // as verifying and extracting, which this switch has always called blue.
      // Amber would invent a failure in the History header, which counts every
      // amber row as one, and push the real failure down the failed-first list.
      expect(sabnzbdStatusTone('Repairing'), StatusTone.info);
    });

    test('queued and in-flight states are informational', () {
      for (final status in [
        'Queued',
        'Downloading',
        'Fetching',
        'Grabbing',
        'Extracting',
        'Verifying',
        'Moving',
        'Running',
        'Propagating',
        'Checking',
      ]) {
        expect(sabnzbdStatusTone(status), StatusTone.info, reason: status);
      }
    });

    test('completed is the only green', () {
      expect(sabnzbdStatusTone('Completed'), StatusTone.success);
    });

    test('an unknown state is left uncoloured rather than guessed', () {
      // SABnzbd gains status words between releases. A table that guesses is
      // how a benign new state arrives on screen painted as a fault.
      expect(sabnzbdStatusTone('Quarantined'), StatusTone.neutral);
      expect(sabnzbdStatusTone(''), StatusTone.neutral);
    });

    test('no status word can reach red', () {
      // Red means the service did not answer, which is the page band's job.
      for (final status in [
        'Failed',
        'Paused',
        'Completed',
        'Downloading',
        'Whatever',
      ]) {
        expect(sabnzbdStatusTone(status), isNot(StatusTone.error));
      }
    });
  });

  group('sabnzbdParseTimeLeft', () {
    test('reads the wire format from the right', () {
      expect(
        sabnzbdParseTimeLeft('0:12:30'),
        const Duration(minutes: 12, seconds: 30),
      );
      expect(
        sabnzbdParseTimeLeft('12:30'),
        const Duration(minutes: 12, seconds: 30),
      );
      expect(
        sabnzbdParseTimeLeft('2:05:00'),
        const Duration(hours: 2, minutes: 5),
      );
    });

    test('a queue with more than a day left is not read as an hour', () {
      // The three-field assumption reads `1:04:00:00` as 1h 4m, and a
      // multi-day queue is exactly the one whose ETA the user came for.
      expect(
        sabnzbdParseTimeLeft('1:04:00:00'),
        const Duration(days: 1, hours: 4),
      );
    });

    test('zero, blank and unreadable are all "no estimate"', () {
      // Not Duration.zero: SABnzbd sends 0:00:00 both for "a second left" and
      // for "nothing is downloading", and only the second happens often.
      expect(sabnzbdParseTimeLeft('0:00:00'), isNull);
      expect(sabnzbdParseTimeLeft(''), isNull);
      expect(sabnzbdParseTimeLeft(null), isNull);
      expect(sabnzbdParseTimeLeft('soon'), isNull);
      expect(sabnzbdParseTimeLeft('0:xx:30'), isNull);
      expect(sabnzbdParseTimeLeft('1:2:3:4:5'), isNull);
    });
  });

  group('sabnzbdEtaLabel', () {
    test('keeps two units at most', () {
      expect(sabnzbdEtaLabel(const Duration(minutes: 7)), '7\u00A0min');
      expect(
        sabnzbdEtaLabel(const Duration(hours: 2, minutes: 5)),
        '2\u00A0h 5\u00A0min',
      );
      expect(sabnzbdEtaLabel(const Duration(hours: 2)), '2\u00A0h');
      expect(
        sabnzbdEtaLabel(const Duration(days: 1, hours: 4)),
        '1\u00A0d 4\u00A0h',
      );
      expect(sabnzbdEtaLabel(const Duration(days: 2)), '2\u00A0d');
    });

    test('never prints a bare zero', () {
      expect(sabnzbdEtaLabel(const Duration(seconds: 30)), '< 1\u00A0min');
      expect(sabnzbdEtaLabel(Duration.zero), isNull);
      expect(sabnzbdEtaLabel(null), isNull);
    });
  });

  group('sabnzbdOverviewReadouts: the em-dash rule', () {
    ServiceKpi eta(SabnzbdQueue queue) =>
        sabnzbdOverviewReadouts(queue).firstWhere((kpi) => kpi.label == 'ETA');

    test('a moving queue reports its estimate', () {
      final kpi = eta(
        _queue(kbPerSec: 2048, timeLeft: '0:07:00', slots: [_slot()]),
      );
      expect(kpi.value, '7\u00A0min');
      expect(kpi.isUnavailable, isFalse);
    });

    test('a paused queue reads an em dash, not 0 min', () {
      // SABnzbd freezes `timeleft` at whatever it last was, so the string is
      // there and the estimate behind it is not. `0 min`, or a stale 7, reads
      // as "about to finish" on a queue that is not moving at all.
      final kpi = eta(
        _queue(
          paused: true,
          kbPerSec: 0,
          timeLeft: '0:07:00',
          slots: [_slot()],
        ),
      );
      expect(kpi.value, ServiceKpi.unavailableValue);
      expect(kpi.value, isNot('0'));
      expect(kpi.isUnavailable, isTrue);
      expect(kpi.note, 'queue stopped');
      // Untoned: the absence is not a fault of SABnzbd's.
      expect(kpi.tone, isNull);
    });

    test('an idle queue names which kind of nothing it is', () {
      expect(eta(_queue(timeLeft: '0:00:00')).note, 'nothing queued');
      expect(
        eta(_queue(timeLeft: '0:00:00', slots: [_slot()])).note,
        'nothing downloading',
      );
    });

    test('the em dash is spoken as a word, never as punctuation', () {
      final kpi = eta(_queue(paused: true, slots: [_slot()]));
      expect(kpi.semanticLabel, 'ETA: unavailable, queue stopped');
    });

    test('a zero the server actually answered is still printed', () {
      // The rule is about figures nobody could compute, not about small ones:
      // a paused queue really is moving 0 bytes a second, and an em dash there
      // would hide a fact the server stated.
      final readouts = sabnzbdOverviewReadouts(
        _queue(paused: true, kbPerSec: 0),
      );
      final speed = readouts.firstWhere((kpi) => kpi.label == 'Speed');
      expect(speed.value, '0\u00A0B/s');
      // …and it wears no tone, because nothing is moving to report.
      expect(speed.tone, isNull);
      expect(readouts.firstWhere((kpi) => kpi.label == 'Queue').value, '0');
    });

    test('speed is informational while bytes are moving', () {
      final readouts = sabnzbdOverviewReadouts(_queue(kbPerSec: 2048));
      expect(
        readouts.firstWhere((kpi) => kpi.label == 'Speed').tone,
        StatusTone.info,
      );
    });

    test('the band is the four figures the client can answer', () {
      // Disk free, the board's fourth tile, is absent rather than faked: no
      // call in SabnzbdClient returns it.
      expect(sabnzbdOverviewReadouts(_queue()).map((kpi) => kpi.label), [
        'Speed',
        'Queue',
        'Left',
        'ETA',
      ]);
    });
  });

  group('sabnzbdQueuePreview', () {
    test('keeps SABnzbd\'s own order and caps the preview', () {
      final section = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(filename: 'first'),
            _slot(filename: 'second'),
            _slot(filename: 'third'),
            _slot(filename: 'fourth'),
            _slot(filename: 'fifth'),
          ],
        ),
        limit: 2,
      );

      // The server's order is the priority order the user set; re-sorting shows
      // the top of a queue that does not exist.
      expect(section.rows.map((row) => row.name), ['first', 'second']);
      // The header still counts them all.
      expect(section.total, 5);
    });

    test('the header counts the queue, not the page it arrived in', () {
      // `mode=queue` is asked for fifty slots and states the real depth in
      // `noofslots_total`. A header taking the page length would read "50 jobs"
      // on a queue of sixty-two for as long as it stayed deep.
      final section = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(filename: 'first'),
            _slot(filename: 'second'),
          ],
          reportedSlots: 62,
        ),
      );

      expect(section.total, 62);
      expect(
        sabnzbdOverviewReadouts(
          _queue(
            slots: [
              _slot(filename: 'first'),
              _slot(filename: 'second'),
            ],
            reportedSlots: 62,
          ),
        ).firstWhere((kpi) => kpi.label == 'Queue').value,
        '62',
      );
    });

    test('a server that reports no depth falls back to the rows in hand', () {
      // Never fabricated, and never below what is on screen: a total smaller
      // than the page it came with describes a different queue.
      expect(sabnzbdQueuePreview(_queue(slots: [_slot()])).total, 1);
      expect(
        sabnzbdQueuePreview(_queue(slots: [_slot()], reportedSlots: 0)).total,
        1,
      );
    });

    test('a row states its progress, size, estimate and category', () {
      final row = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(
              filename: 'Dune.Part.Two.2024.2160p',
              status: 'Downloading',
              percentage: 72,
              mbLeft: 1024,
              timeLeft: '0:02:00',
              category: 'movies',
            ),
          ],
        ),
      ).rows.single;

      expect(row.name, 'Dune.Part.Two.2024.2160p');
      expect(
        row.detail,
        'downloading · 1.0\u00A0GB left · 2\u00A0min · movies',
      );
      expect(row.percentLabel, '72%');
      expect(row.tone, StatusTone.info);
      expect(row.isFault, isFalse);
    });

    test('a row states the job\'s size beside what is left of it', () {
      // `1.0 GB left` alone is the same sentence at 30% and at 95%. The total
      // rides in the same `mode=queue` slot as the remainder, so the row that
      // had one figure had both available all along.
      final row = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(
              filename: 'Dune.Part.Two.2024.2160p',
              status: 'Downloading',
              percentage: 72,
              mbLeft: 1024,
              mb: 4096,
              timeLeft: '0:02:00',
              category: 'movies',
            ),
          ],
        ),
      ).rows.single;

      expect(
        row.detail,
        'downloading · 1.0\u00A0GB left of 4.0\u00A0GB · 2\u00A0min · movies',
      );
      expect(
        row.spoken,
        'Dune.Part.Two.2024.2160p, 72 percent downloaded, downloading, '
        '1.0\u00A0GB left of 4.0\u00A0GB, 2\u00A0min, movies',
      );
    });

    test('a slot with no total drops the clause rather than dashing it', () {
      // Same rule the ETA below follows: the section prints what the server
      // stood behind. Never `of 0 B`, and never a dash inside a dotted line,
      // which reads as a figure that failed to load.
      final row = sabnzbdQueuePreview(
        _queue(slots: [_slot(status: 'Downloading', mbLeft: 1024)]),
      ).rows.single;

      expect(row.detail, 'downloading · 1.0\u00A0GB left · 5\u00A0min');
      expect(row.detail, isNot(contains('of')));
      expect(row.detail, isNot(contains('—')));
      expect(row.detail, isNot(contains('0\u00A0B')));
    });

    test('a queued job shows 0% and no invented estimate', () {
      // 0% is a percentage the server answered, "not started", so it prints.
      // The ETA does not: a queued job has none, and a dash inside a dotted
      // line reads as a value that failed to load rather than one that was
      // never claimed.
      final row = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(status: 'Queued', percentage: 0, mbLeft: 1024, timeLeft: ''),
          ],
        ),
      ).rows.single;

      expect(row.percentLabel, '0%');
      expect(row.detail, 'queued · 1.0\u00A0GB left');
      expect(row.detail, isNot(contains('—')));
    });

    test('a paused job is neutral and a failed one is a fault', () {
      final rows = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(filename: 'held', status: 'Paused'),
            _slot(filename: 'broken', status: 'Failed'),
          ],
        ),
      ).rows;

      expect(rows[0].tone, StatusTone.neutral);
      expect(rows[0].isFault, isFalse);
      expect(rows[1].isFault, isTrue);
    });

    test('the header facts come from the queue, paused included', () {
      final section = sabnzbdQueuePreview(
        _queue(paused: true, mbLeft: 1024, slots: [_slot()]),
      );
      expect(section.sizeLeftLabel, '1.0\u00A0GB');
      expect(section.paused, isTrue);
    });

    test('a row is spoken as one sentence, with the dots as pauses', () {
      final row = sabnzbdQueuePreview(
        _queue(
          slots: [
            _slot(
              filename: 'Severance.S02E05',
              status: 'Queued',
              percentage: 0,
              mbLeft: 1024,
              timeLeft: '',
              category: 'tv',
            ),
          ],
        ),
      ).rows.single;

      expect(
        row.spoken,
        'Severance.S02E05, 0 percent downloaded, queued, 1.0\u00A0GB left, tv',
      );
      expect(row.spoken, isNot(contains('·')));
    });
  });

  group('sabnzbdHistoryToday', () {
    final now = DateTime(2026, 9, 16, 14, 30);

    test('lifts failures above everything, newest first inside each group', () {
      final section = sabnzbdHistoryToday([
        _history(name: 'ok-old', completed: DateTime(2026, 9, 16, 8)),
        _history(name: 'ok-new', completed: DateTime(2026, 9, 16, 13)),
        _history(
          name: 'bad-old',
          status: 'Failed',
          completed: DateTime(2026, 9, 16, 7),
        ),
        _history(
          name: 'bad-new',
          status: 'Failed',
          completed: DateTime(2026, 9, 16, 12),
        ),
      ], now: now);

      expect(section.rows.map((row) => row.name), [
        'bad-new',
        'bad-old',
        'ok-new',
        'ok-old',
      ]);
      expect(section.failed, 2);
      expect(section.completed, 2);
    });

    test('yesterday is out, however recent', () {
      // The header says `today`, and a heading is a promise: a job that landed
      // at 23:50 yesterday is twenty minutes old and still not today's.
      final section = sabnzbdHistoryToday([
        _history(name: 'yesterday', completed: DateTime(2026, 9, 15, 23, 50)),
        _history(name: 'today', completed: DateTime(2026, 9, 16, 0, 10)),
      ], now: DateTime(2026, 9, 16, 0, 20));

      expect(section.rows.map((row) => row.name), ['today']);
      expect(section.completed, 1);
      expect(section.dayCovered, isTrue);
    });

    test(
      'a record with no timestamp is dropped rather than assumed recent',
      () {
        final section = sabnzbdHistoryToday([
          _history(name: 'undated', completed: null),
        ], now: now);
        expect(section.rows, isEmpty);
        expect(section.completed, 0);
        expect(section.failed, 0);
      },
    );

    test('the counts cover the window, not the rows drawn', () {
      // The header says `12 completed` over four rows without contradicting
      // itself, which only works if the count is taken before the cut.
      final section = sabnzbdHistoryToday(
        [
          for (var i = 0; i < 12; i++)
            _history(name: 'job $i', completed: DateTime(2026, 9, 16, 9, i)),
        ],
        now: now,
        limit: 4,
      );

      expect(section.rows, hasLength(4));
      expect(section.completed, 12);
      // Twelve records against a page of a hundred: the server had nothing more
      // to give, so twelve is the day and not a floor under it.
      expect(section.dayCovered, isTrue);
    });

    test('a page that never reached yesterday states a floor, not a day', () {
      // Every record the server returned is today's and the page came back
      // full: there is no way to know what fell off the end, including a
      // failure this section exists to lift, which is why the header must not
      // state these counts as the day.
      final section = sabnzbdHistoryToday(
        [
          for (var i = 0; i < 20; i++)
            _history(name: 'job $i', completed: DateTime(2026, 9, 16, 9, i)),
        ],
        now: now,
        pageSize: 20,
      );

      expect(section.completed, 20);
      expect(section.dayCovered, isFalse);
    });

    test('a page that crossed midnight covers the day', () {
      // One record from before today proves every one of today's is in hand,
      // however full the page came back.
      final section = sabnzbdHistoryToday(
        [
          for (var i = 0; i < 19; i++)
            _history(name: 'job $i', completed: DateTime(2026, 9, 16, 9, i)),
          _history(name: 'yesterday', completed: DateTime(2026, 9, 15, 22)),
        ],
        now: now,
        pageSize: 20,
      );

      expect(section.completed, 19);
      expect(section.rows.map((row) => row.name), isNot(contains('yesterday')));
      expect(section.dayCovered, isTrue);
    });

    test('an undated record proves nothing about the window', () {
      // It is dropped from the rows, counted against the page like any other
      // record, and never read as a record from before today.
      final section = sabnzbdHistoryToday(
        [
          for (var i = 0; i < 19; i++)
            _history(name: 'job $i', completed: DateTime(2026, 9, 16, 9, i)),
          _history(name: 'undated', completed: null),
        ],
        now: now,
        pageSize: 20,
      );

      expect(section.completed, 19);
      expect(section.dayCovered, isFalse);
    });

    test('a failed row leads with the server\'s own reason', () {
      final entry = sabnzbdHistoryToday([
        _history(
          name: 'Killers.of.the.Flower.Moon.2023.2160p',
          status: 'Failed',
          failMessage: 'missing 14 articles',
          bytes: 0,
          category: 'movies',
          completed: DateTime(2026, 9, 16, 13, 30),
        ),
      ], now: now).rows.single;

      expect(entry.failed, isTrue);
      expect(entry.event, 'failed');
      expect(entry.detail, 'missing 14 articles · 1\u00A0h ago · movies');
    });

    test('a completed row is spoken as one sentence', () {
      final entry = sabnzbdHistoryToday([
        _history(
          name: 'Andor.S02E02.1080p.WEB-DL',
          bytes: 1024 * 1024 * 1024,
          category: 'tv',
          completed: DateTime(2026, 9, 16, 12, 30),
        ),
      ], now: now).rows.single;

      expect(entry.failed, isFalse);
      expect(
        entry.spoken,
        'Andor.S02E02.1080p.WEB-DL, completed, 1.0\u00A0GB, 2\u00A0h ago, tv',
      );
      expect(entry.spoken, isNot(contains('·')));
    });

    test('a job par2 is repairing is not counted as a failure', () {
      // Repair is the recovery working. Counted as a failure it would make the
      // header read `1 failed` on a day when nothing broke, and on the day
      // something does, put the real failure second.
      final section = sabnzbdHistoryToday([
        _history(
          name: 'Dune.Part.Two.2024',
          status: 'Repairing',
          completed: DateTime(2026, 9, 16, 14),
        ),
      ], now: now);

      expect(section.failed, 0);
      expect(section.completed, 1);
      expect(section.rows.single.failed, isFalse);
      expect(section.rows.single.tone, StatusTone.info);
    });

    test('a job still post-processing counts as work that got done', () {
      // Not a third number in a header with room for two, and emphatically not
      // a failure: unpacking is on its way to completed.
      final section = sabnzbdHistoryToday([
        _history(
          name: 'Poor.Things.2023',
          status: 'Extracting',
          completed: DateTime(2026, 9, 16, 14),
        ),
      ], now: now);

      expect(section.completed, 1);
      expect(section.failed, 0);
      expect(section.rows.single.tone, StatusTone.info);
    });
  });
}

// ─── Builders ───────────────────────────────────────────────────────────────

SabnzbdQueue _queue({
  bool paused = false,
  double kbPerSec = 0,
  double mbLeft = 0,
  String timeLeft = '0:00:00',
  List<SabnzbdQueueSlot> slots = const [],
  int? reportedSlots,
}) => SabnzbdQueue(
  paused: paused,
  status: paused ? 'Paused' : 'Downloading',
  kbPerSec: kbPerSec,
  mbLeft: mbLeft,
  mb: mbLeft,
  timeLeft: timeLeft,
  slots: slots,
  reportedSlots: reportedSlots,
);

SabnzbdQueueSlot _slot({
  String filename = 'Release',
  String status = 'Downloading',
  int percentage = 50,
  double mbLeft = 100,
  double? mb,
  String timeLeft = '0:05:00',
  String category = '',
}) => SabnzbdQueueSlot(
  nzoId: 'SABnzbd_nzo_$filename',
  filename: filename,
  status: status,
  percentage: percentage,
  category: category,
  timeLeft: timeLeft,
  mbLeft: mbLeft,
  mb: mb,
);

SabnzbdHistorySlot _history({
  String name = 'Release',
  String status = 'Completed',
  String category = '',
  int bytes = 0,
  String? failMessage,
  required DateTime? completed,
}) => SabnzbdHistorySlot(
  nzoId: 'SABnzbd_nzo_$name',
  name: name,
  status: status,
  category: category,
  bytes: bytes,
  completed: completed,
  failMessage: failMessage,
);

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_provider.dart';

/// Every rule on the NZBGet Overview is a top-level pure function taking an
/// explicit `now`, so each boundary is exercised here without a clock, a
/// container or a widget.
void main() {
  group('nzbgetGroupState', () {
    test('reads NZBGet\'s own queue vocabulary', () {
      expect(nzbgetGroupState('DOWNLOADING'), NzbgetGroupState.downloading);
      expect(nzbgetGroupState('FETCHING'), NzbgetGroupState.fetching);
      expect(nzbgetGroupState('PAUSED'), NzbgetGroupState.paused);
      expect(nzbgetGroupState('QUEUED'), NzbgetGroupState.queued);
      // The half-dozen post-processing stages collapse to one state, because
      // they differ in stage and not in tone.
      expect(nzbgetGroupState('REPAIRING'), NzbgetGroupState.postProcessing);
      expect(nzbgetGroupState('UNPACKING'), NzbgetGroupState.postProcessing);
      expect(nzbgetGroupState('PP_QUEUED'), NzbgetGroupState.postProcessing);
    });

    test('a job with no status is in the queue, not in an unknown state', () {
      expect(nzbgetGroupState(''), NzbgetGroupState.queued);
      expect(nzbgetGroupState('   '), NzbgetGroupState.queued);
    });

    test('a status this app has not met is unknown, never guessed', () {
      expect(nzbgetGroupState('TELEPORTING'), NzbgetGroupState.unknown);
    });

    test('nothing in the queue is amber', () {
      // The queue has no fault state: a broken job leaves it for history, so
      // an amber here would be the backlog mistake in its download form.
      for (final state in NzbgetGroupState.values) {
        expect(state.tone, isNot(StatusTone.warning), reason: state.name);
        expect(state.tone, isNot(StatusTone.error), reason: state.name);
      }
      // And a job the user paused is neutral, not "activity".
      expect(NzbgetGroupState.paused.tone, StatusTone.neutral);
    });
  });

  group('nzbgetGroupStageLabel', () {
    test('keeps the stage, which is what tells a repair from an unpack', () {
      expect(nzbgetGroupStageLabel('REPAIRING'), 'repairing');
      expect(nzbgetGroupStageLabel('UNPACKING'), 'unpacking');
      expect(nzbgetGroupStageLabel('LOADING_PARS'), 'par-check');
      expect(nzbgetGroupStageLabel('PP_QUEUED'), 'post-processing');
    });

    test('humanises a stage it does not know instead of inventing a word', () {
      expect(nzbgetGroupStageLabel('SOME_NEW_STAGE'), 'some new stage');
    });
  });

  group('nzbgetEtaLabel', () {
    test('a stopped queue has no ETA: never "0 min", never "∞"', () {
      expect(
        nzbgetEtaLabel(remainingMegabytes: 2048, rateBytesPerSecond: 0),
        isNull,
      );
      expect(
        nzbgetEtaLabel(remainingMegabytes: 2048, rateBytesPerSecond: -1),
        isNull,
      );
    });

    test('an empty queue has no wait to describe', () {
      expect(
        nzbgetEtaLabel(remainingMegabytes: 0, rateBytesPerSecond: 3100000),
        isNull,
      );
    });

    test('renders the board\'s figure', () {
      // The board's own pair: 2.1 GB still to fetch at 3.1 MB/s.
      expect(
        nzbgetEtaLabel(remainingMegabytes: 2150, rateBytesPerSecond: 3100000),
        'about 12\u00A0min',
      );
    });

    test('rounds up past the minute, the hour and the day', () {
      expect(
        nzbgetEtaLabel(remainingMegabytes: 1, rateBytesPerSecond: 10000000),
        'about a minute',
      );
      expect(
        nzbgetEtaLabel(remainingMegabytes: 9000, rateBytesPerSecond: 1048576),
        'about 2\u00A0h 30\u00A0min',
      );
      expect(
        nzbgetEtaLabel(remainingMegabytes: 7200, rateBytesPerSecond: 1048576),
        'about 2\u00A0h',
      );
      expect(
        nzbgetEtaLabel(remainingMegabytes: 180000, rateBytesPerSecond: 1048576),
        'about 2 days',
      );
    });
  });

  group('nzbgetQueueSection', () {
    test('counts what is moving and what is post-processing', () {
      final section = nzbgetQueueSection(
        [
          _group(name: 'Silo', status: 'DOWNLOADING'),
          _group(name: 'Zone', status: 'REPAIRING'),
          _group(name: 'Andor', status: 'QUEUED'),
        ],
        status: const NzbgetStatus(
          downloadRateBytes: 3100000,
          remainingSizeMb: 2150,
          paused: false,
        ),
      );

      expect(section.downloading, 1);
      expect(section.postProcessing, 1);
      expect(section.total, 3);
      expect(
        section.subtitle,
        '1 downloading · 1 post-processing · 2.1\u00A0GB left · about 12\u00A0min',
      );
    });

    test('a status that did not answer costs the clauses, not the rows', () {
      // The one rule this section exists to hold: a silent `status` must not
      // print "0 B left" or "about 0 min", and must not take the queue down
      // with it.
      final section = nzbgetQueueSection([
        _group(name: 'Silo', status: 'DOWNLOADING'),
      ], status: null);

      expect(section.rows, hasLength(1));
      expect(section.remainingLabel, isNull);
      expect(section.etaLabel, isNull);
      expect(section.subtitle, '1 downloading');
    });

    test('a queue nobody is working on still says how big it is', () {
      final section = nzbgetQueueSection([
        _group(name: 'Silo', status: 'PAUSED'),
        _group(name: 'Andor', status: 'PAUSED'),
      ], status: null);

      expect(section.subtitle, '2 jobs');
    });

    test('an idle queue says so rather than printing a blank line', () {
      // The commonest state of a download client, and the one where every
      // clause is guarded off at once: no downloading, no post-processing, no
      // jobs to count, and a `status` whose remaining total is zero. An empty
      // string is not a shorter header: `SectionHeader` treats a non-null
      // subtitle as a subtitle, so it would draw a blank line under the word
      // Queue and speak "Queue, " with a dangling comma.
      final section = nzbgetQueueSection(
        const [],
        status: const NzbgetStatus(
          downloadRateBytes: 0,
          remainingSizeMb: 0,
          paused: false,
        ),
      );

      expect(section.rows, isEmpty);
      expect(section.total, 0);
      expect(section.remainingLabel, isNull);
      expect(section.etaLabel, isNull);
      expect(section.subtitle, 'nothing queued');
      expect(section.subtitle, isNotEmpty);
    });

    test('preserves the server\'s order and caps the preview', () {
      final section = nzbgetQueueSection([
        _group(name: 'First', status: 'DOWNLOADING'),
        _group(name: 'Second', status: 'QUEUED'),
        _group(name: 'Third', status: 'QUEUED'),
        _group(name: 'Fourth', status: 'QUEUED'),
      ], limit: 3);

      // Server order, because `listgroups` answers in the order NZBGet will
      // work through the queue.
      expect(section.rows.map((row) => row.name), ['First', 'Second', 'Third']);
      // …while the header still counts all four.
      expect(section.total, 4);
    });

    test('a job whose size the server did not report shows no percentage', () {
      final row = nzbgetQueueEntry(
        _group(name: 'Sizeless', status: 'DOWNLOADING', fileSizeMb: null),
      );

      // Never "0%": that reading says "stuck", which nobody established.
      expect(row.percentLabel, isNull);
      expect(row.detail, 'tv · downloading');
      expect(row.spoken, 'Sizeless, tv, downloading');
    });

    test('a job whose remaining size nobody reported shows no percentage', () {
      // Never "100%" either, which is what a `0` default for the remaining
      // size used to compute: `(size - 0) / size` == 1, so a job the server
      // said nothing about drew a full bar and read as finished.
      final row = nzbgetQueueEntry(
        _group(
          name: 'Unmeasured',
          status: 'DOWNLOADING',
          fileSizeMb: 4915,
          remainingSizeMb: null,
        ),
      );

      expect(row.percentLabel, isNull);
      // The size the server *did* report still prints. It is a fact, and the
      // only one of the two that was answered.
      expect(row.detail, 'tv · downloading · 4.8\u00A0GB');
    });

    test('a row is one sentence, with the dots read as commas', () {
      final row = nzbgetQueueEntry(
        _group(
          name: 'Silo.S03E01.2160p.WEB-DL',
          status: 'DOWNLOADING',
          fileSizeMb: 4915,
          remainingSizeMb: 2162,
        ),
      );

      expect(row.percentLabel, '56%');
      expect(row.detail, 'tv · downloading · 4.8\u00A0GB');
      expect(
        row.spoken,
        'Silo.S03E01.2160p.WEB-DL, tv, downloading, 4.8\u00A0GB, 56 percent',
      );
    });
  });

  group('nzbgetHistoryOutcome', () {
    test('a failure names the reason in words, not in NZBGet\'s code', () {
      expect(nzbgetHistoryOutcome('FAILURE/PAR'), (
        NzbgetHistoryOutcome.failed,
        'par repair',
      ));
      expect(nzbgetHistoryOutcome('WARNING/DAMAGED'), (
        NzbgetHistoryOutcome.warned,
        'damaged',
      ));
    });

    test('"it worked" is not repeated as a second clause', () {
      expect(nzbgetHistoryOutcome('SUCCESS/ALL'), (
        NzbgetHistoryOutcome.succeeded,
        null,
      ));
      expect(nzbgetHistoryOutcome('SUCCESS/UNPACK'), (
        NzbgetHistoryOutcome.succeeded,
        'unpack',
      ));
    });

    test('a deliberate removal is NEUTRAL, never amber', () {
      // The single most common way the tone rule is broken: "deleted" sounds
      // like damage and is the user, or a dupe rule, getting what they asked
      // for.
      final (outcome, reason) = nzbgetHistoryOutcome('DELETED/DUPE');
      expect(outcome, NzbgetHistoryOutcome.deleted);
      expect(outcome.tone, StatusTone.neutral);
      expect(outcome.isFault, isFalse);
      expect(reason, 'duplicate');
    });

    test('only a real fault is amber', () {
      expect(NzbgetHistoryOutcome.failed.tone, StatusTone.warning);
      expect(NzbgetHistoryOutcome.warned.tone, StatusTone.warning);
      expect(NzbgetHistoryOutcome.succeeded.tone, StatusTone.success);
      expect(NzbgetHistoryOutcome.unknown.tone, StatusTone.neutral);
    });

    test(
      'a URL record the daemon could not fetch is a FAULT, not "finished"',
      () {
        // `history(false)`, the call the client makes, returns URL-kind records
        // too, and their whole `Status` is one word with no `/`. Split on the
        // slash they would become their own family, match no arm and land in
        // `unknown`: neutral ink, the word "finished", uncounted in `failed`. The
        // one thing on this page that must make someone look would be the one
        // thing that reads as fine.
        final (failure, failureReason) = nzbgetHistoryOutcome('URL_FAILURE');
        expect(failure, NzbgetHistoryOutcome.failed);
        expect(failure.tone, StatusTone.warning);
        expect(failure.isFault, isTrue);
        expect(failureReason, 'could not fetch the NZB');

        expect(nzbgetHistoryOutcome('URL_SCAN_FAILURE'), (
          NzbgetHistoryOutcome.failed,
          'the NZB could not be read',
        ));
      },
    );

    test('a URL record that did what it said is not a fault', () {
      // The link was fetched; the scan script chose not to look at it. Not
      // damage, so not amber: the backlog mistake in reverse.
      expect(nzbgetHistoryOutcome('URL_SUCCESS'), (
        NzbgetHistoryOutcome.succeeded,
        null,
      ));
      expect(nzbgetHistoryOutcome('URL_SCAN_SKIPPED'), (
        NzbgetHistoryOutcome.succeeded,
        'scan skipped',
      ));
      // NZBGet's own "I do not know", kept distinct from ours.
      expect(nzbgetHistoryOutcome('URL_UNKNOWN'), (
        NzbgetHistoryOutcome.unknown,
        null,
      ));
    });

    test('an unknown status is passed through rather than guessed', () {
      expect(nzbgetHistoryOutcome('QUANTUM/FLUX'), (
        NzbgetHistoryOutcome.unknown,
        'flux',
      ));
      expect(nzbgetHistoryOutcome(''), (NzbgetHistoryOutcome.unknown, null));
    });
  });

  group('nzbgetHistoryToday', () {
    final now = DateTime(2026, 9, 16, 14, 0);

    test('"today" is a local calendar day, not the last 24 hours', () {
      final section = nzbgetHistoryToday([
        // 23:50 yesterday: twenty minutes older than the window, and out.
        _item(name: 'Yesterday', at: DateTime(2026, 9, 15, 23, 50)),
        _item(name: 'This morning', at: DateTime(2026, 9, 16, 0, 10)),
      ], now: now);

      expect(section.rows.map((row) => row.name), ['This morning']);
      expect(section.completed, 1);
    });

    test('a record with no timestamp is dropped, not sorted to an end', () {
      final section = nzbgetHistoryToday([
        const NzbgetHistoryItem(
          id: 1,
          name: 'Undated',
          status: 'SUCCESS/ALL',
          category: '',
        ),
      ], now: now);

      expect(section.rows, isEmpty);
      expect(section.completed, 0);
    });

    test('faults come first, then the clock', () {
      final section = nzbgetHistoryToday([
        _item(
          name: 'Andor',
          at: DateTime(2026, 9, 16, 9),
          status: 'SUCCESS/ALL',
        ),
        _item(
          name: 'Slow Horses',
          at: DateTime(2026, 9, 16, 6),
          status: 'SUCCESS/ALL',
        ),
        _item(
          name: 'Sugar',
          at: DateTime(2026, 9, 16, 11),
          status: 'FAILURE/PAR',
        ),
      ], now: now);

      // The mobile board's own instruction: history, failed first.
      expect(section.rows.map((row) => row.name), [
        'Sugar',
        'Andor',
        'Slow Horses',
      ]);
    });

    test('the header counts the day, the rows are only the preview', () {
      final section = nzbgetHistoryToday([
        for (var i = 0; i < 6; i++)
          _item(
            name: 'Done $i',
            at: DateTime(2026, 9, 16, 8, i),
            status: 'SUCCESS/ALL',
          ),
        _item(
          name: 'Sugar',
          at: DateTime(2026, 9, 16, 11),
          status: 'FAILURE/PAR',
        ),
        // A dupe NZBGet threw away on purpose is in neither count: it is not
        // news, and counting it beside the failures would inflate the one
        // number on this page that should make someone look.
        _item(
          name: 'Dupe',
          at: DateTime(2026, 9, 16, 12),
          status: 'DELETED/DUPE',
        ),
      ], now: now);

      expect(section.completed, 6);
      expect(section.failed, 1);
      expect(section.warned, 0);
      expect(section.subtitle, 'today · 6 completed · 1 failed');
      expect(section.rows, hasLength(nzbgetHistoryTodayLimit));
    });

    test('a row is one sentence', () {
      final section = nzbgetHistoryToday([
        _item(
          name: 'Sugar.S02E01.1080p.WEB-DL',
          at: DateTime(2026, 9, 16, 11),
          status: 'FAILURE/PAR',
          category: 'tv',
        ),
      ], now: now);

      final row = section.rows.single;
      expect(row.headline, 'Sugar.S02E01.1080p.WEB-DL · failed');
      expect(row.detail, 'par repair · tv · 3\u00A0h ago');
      expect(
        row.spoken,
        'Sugar.S02E01.1080p.WEB-DL, failed, par repair, tv, 3\u00A0h ago',
      );
    });

    test(
      'an NZB the daemon never fetched is counted and sorted as a fault',
      () {
        // The end-to-end of the URL-kind trap: a `URL_FAILURE` must reach the
        // `failed` count the header states and the top of the faults-first
        // preview, not sit in neutral ink halfway down reading "finished".
        final section = nzbgetHistoryToday([
          _item(
            name: 'Andor',
            at: DateTime(2026, 9, 16, 12),
            status: 'SUCCESS/ALL',
          ),
          _item(
            name: 'Sugar',
            at: DateTime(2026, 9, 16, 9),
            status: 'URL_FAILURE',
          ),
        ], now: now);

        expect(section.failed, 1);
        expect(section.completed, 1);
        expect(section.subtitle, 'today · 1 completed · 1 failed');
        // Older than the success beside it, and still first.
        expect(section.rows.map((row) => row.name), ['Sugar', 'Andor']);
        expect(section.rows.first.headline, 'Sugar · failed');
        expect(section.rows.first.tone, StatusTone.warning);
      },
    );

    test('a day with nothing on it says nothing rather than zeroes', () {
      final section = nzbgetHistoryToday(const [], now: now);

      expect(section.rows, isEmpty);
      // No "0 completed · 0 failed": the section's own empty note carries it.
      expect(section.subtitle, 'today');
    });
  });
}

NzbgetGroup _group({
  required String name,
  required String status,
  String category = 'tv',
  int? fileSizeMb = 4915,
  int? remainingSizeMb = 2162,
}) => NzbgetGroup(
  nzbId: name.hashCode,
  name: name,
  status: status,
  category: category,
  fileSizeMb: fileSizeMb,
  remainingSizeMb: remainingSizeMb,
);

NzbgetHistoryItem _item({
  required String name,
  required DateTime at,
  String status = 'SUCCESS/ALL',
  String category = '',
}) => NzbgetHistoryItem(
  id: name.hashCode,
  name: name,
  status: status,
  category: category,
  time: at,
);

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_provider.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';

/// The window rules, the sentinels and the tone rule, as pure functions.
///
/// Every one of these takes its own `now`, so nothing here waits, sleeps or
/// depends on the machine's clock, which is the whole reason the rules were
/// written as top-level functions rather than inside the widgets that draw
/// them.
void main() {
  final now = DateTime(2026, 9, 16, 15, 0);

  group('qbittorrentIdleLabel: the last_activity sentinel', () {
    test('qB\'s 0 "never moved" sentinel says nothing, never 1970', () {
      // The bug this exists to stop: 0 read as an epoch is 1 Jan 1970, and the
      // row would have claimed the torrent stalled 20,000 days ago.
      expect(qbittorrentIdleLabel(0, now: now), isNull);
      expect(qbittorrentIdleLabel(-1, now: now), isNull);
    });

    test('a timestamp in the future is clock skew, not a negative age', () {
      final ahead = now.add(const Duration(hours: 2));
      expect(
        qbittorrentIdleLabel(ahead.millisecondsSinceEpoch ~/ 1000, now: now),
        isNull,
      );
    });

    test('under a minute is the gap between two polls, not an idle period', () {
      final recent = now.subtract(const Duration(seconds: 59));
      expect(
        qbittorrentIdleLabel(recent.millisecondsSinceEpoch ~/ 1000, now: now),
        isNull,
      );
    });

    test('the ladder walks minutes, then hours, then days', () {
      String? at(Duration ago) => qbittorrentIdleLabel(
        now.subtract(ago).millisecondsSinceEpoch ~/ 1000,
        now: now,
      );

      expect(at(const Duration(minutes: 1)), '1\u00A0min');
      expect(at(const Duration(minutes: 42)), '42\u00A0min');
      // The boundary lands on the hour, not a minute either side.
      expect(at(const Duration(minutes: 59)), '59\u00A0min');
      expect(at(const Duration(minutes: 60)), '1\u00A0h');
      expect(at(const Duration(hours: 23)), '23\u00A0h');
      expect(at(const Duration(hours: 24)), '1 day');
      expect(at(const Duration(days: 3)), '3 days');
    });
  });

  group('qbittorrentPercentLabel', () {
    test('rounds to nearest, but 99.6% never claims to be finished', () {
      expect(qbittorrentPercentLabel(0.996), '99%');
      expect(qbittorrentPercentLabel(1.0), '100%');
      expect(qbittorrentPercentLabel(0.0), '0%');
      expect(qbittorrentPercentLabel(0.924), '92%');
      expect(qbittorrentPercentLabel(0.925), '93%');
    });

    test('a value outside 0..1 is clamped rather than printed', () {
      expect(qbittorrentPercentLabel(1.4), '100%');
      expect(qbittorrentPercentLabel(-0.2), '0%');
    });
  });

  group('qbittorrentFaultKindOf: the tone rule, five arms', () {
    test('stalled is a FAULT: the user did not ask for this', () {
      expect(
        qbittorrentFaultKindOf(_torrent(state: 'stalledDL')),
        QbittorrentFaultKind.stalled,
      );
      expect(QbittorrentFaultKind.stalled.tone, StatusTone.warning);
    });

    test('errored and missingFiles are faults, and are told apart', () {
      expect(
        qbittorrentFaultKindOf(_torrent(state: 'error')),
        QbittorrentFaultKind.errored,
      );
      // The model folds both into TorrentState.error; the raw string is what
      // separates "libtorrent gave up" from "your disk moved".
      expect(
        qbittorrentFaultKindOf(_torrent(state: 'missingFiles')),
        QbittorrentFaultKind.missingFiles,
      );
    });

    test('a deliberately paused torrent is BACKLOG and is never a fault', () {
      // The single most common way the tone rule gets broken in a download
      // client. All four spellings qB has used over the versions.
      for (final state in ['pausedDL', 'pausedUP', 'stoppedDL', 'stopped']) {
        expect(
          qbittorrentFaultKindOf(_torrent(state: state)),
          isNull,
          reason: '$state is the user\'s own choice, not damage',
        );
      }
    });

    test('healthy and queued states are not faults either', () {
      for (final state in [
        'downloading',
        'uploading',
        'stalledUP',
        'queuedDL',
        'checkingDL',
        'metaDL',
      ]) {
        expect(qbittorrentFaultKindOf(_torrent(state: state)), isNull);
      }
    });
  });

  group('qbittorrentFaultRows', () {
    test('a stalled row states progress, how long, and who is left', () {
      final rows = qbittorrentFaultRows([
        _torrent(
          name: 'The.Zone.of.Interest.2023',
          state: 'stalledDL',
          progress: 0.18,
          seeders: 3,
          lastActivity:
              now
                  .subtract(const Duration(minutes: 42))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      ], now: now);

      final row = rows.single;
      expect(row.tone, StatusTone.warning);
      expect(row.headline, 'Stuck\u00A0· The.Zone.of.Interest.2023');
      expect(row.detail, '18%\u00A0· idle 42\u00A0min\u00A0· 3 seeds');
    });

    test('zero seeds is stated: it is the reason, not a missing figure', () {
      final rows = qbittorrentFaultRows([
        _torrent(state: 'stalledDL', progress: 0.5, seeders: 0),
      ], now: now);

      expect(rows.single.detail, contains('no seeds'));
    });

    test('a torrent qB never saw move omits the clause, not prints 0', () {
      final rows = qbittorrentFaultRows([
        _torrent(
          state: 'stalledDL',
          progress: 0.5,
          seeders: 2,
          lastActivity: 0,
        ),
      ], now: now);

      expect(rows.single.detail, '50%\u00A0· 2 seeds');
      expect(rows.single.detail, isNot(contains('idle')));
    });

    test('paused torrents never reach the section at any position', () {
      final rows = qbittorrentFaultRows([
        _torrent(name: 'Paused', state: 'pausedDL'),
        _torrent(name: 'Stopped', state: 'stoppedUP'),
      ], now: now);

      expect(rows, isEmpty);
    });

    test('errored leads, then missing files, then stalled', () {
      final rows = qbittorrentFaultRows([
        _torrent(name: 'c', state: 'stalledDL'),
        _torrent(name: 'a', state: 'missingFiles'),
        _torrent(name: 'b', state: 'error'),
      ], now: now);

      expect(rows.map((r) => r.kind), [
        QbittorrentFaultKind.errored,
        QbittorrentFaultKind.missingFiles,
        QbittorrentFaultKind.stalled,
      ]);
    });

    test('within a kind the one wrong for longest is named first', () {
      final rows = qbittorrentFaultRows([
        _torrent(
          name: 'recent',
          state: 'stalledDL',
          lastActivity:
              now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
              1000,
        ),
        _torrent(
          name: 'ancient',
          state: 'stalledDL',
          lastActivity:
              now.subtract(const Duration(days: 4)).millisecondsSinceEpoch ~/
              1000,
        ),
      ], now: now);

      // Two of a kind are one row, and its names keep the order: the one
      // wrong for longest first.
      expect(rows.single.headline, '2 downloads stuck');
      expect(rows.single.detail, 'ancient, recent');
    });

    test('the row speaks one sentence, with the dots turned into commas', () {
      final rows = qbittorrentFaultRows([
        _torrent(
          name: 'Dune.Part.Two',
          state: 'stalledDL',
          progress: 0.18,
          seeders: 3,
          lastActivity:
              now
                  .subtract(const Duration(minutes: 42))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      ], now: now);

      expect(
        rows.single.spoken,
        'Stuck, Dune.Part.Two, 18 percent, idle 42\u00A0min, 3 seeds',
      );
      expect(rows.single.spoken, isNot(contains('·')));
    });

    test('a broken server cannot print forty rows: a state is one row', () {
      final rows = qbittorrentFaultRows([
        for (var i = 0; i < 20; i++) _torrent(name: 'x$i', state: 'error'),
      ], now: now);

      expect(rows, hasLength(1));
      expect(rows.single.headline, '20 torrents errored');
      expect(rows.single.detail, 'x0, x1, x10 and 17 more');
      expect(rows.single.count, 20);
    });

    test('the cap on rows still holds, worst kind first', () {
      final rows = qbittorrentFaultRows(
        [
          _torrent(name: 's', state: 'stalledDL'),
          _torrent(name: 'e', state: 'error'),
          _torrent(name: 'm', state: 'missingFiles'),
        ],
        now: now,
        limit: 2,
      );

      expect(rows.map((row) => row.kind), [
        QbittorrentFaultKind.errored,
        QbittorrentFaultKind.missingFiles,
      ]);
    });
  });

  group('qbittorrentFaultRows leads to where the fault is fixed', () {
    test('one torrent opens its own page, by its hash, on the connection that '
        'listed it', () {
      final rows = qbittorrentFaultRows(
        [_torrent(name: 'a', state: 'stalledDL', hash: 'abc123')],
        now: now,
        instanceId: 'qbittorrent',
      );

      expect(
        rows.single.door,
        const AttentionDoor.download(instanceId: 'qbittorrent', key: 'abc123'),
      );
      expect(rows.single.hash, 'abc123');
    });

    test('several of a state are one row that opens the Queue tab, about no '
        'one torrent', () {
      final rows = qbittorrentFaultRows([
        _torrent(name: 'a', state: 'error', hash: '1'),
        _torrent(name: 'b', state: 'error', hash: '2'),
        _torrent(name: 'c', state: 'missingFiles', hash: '3'),
        _torrent(name: 'd', state: 'missingFiles', hash: '4'),
      ], now: now);

      expect(rows.map((row) => row.headline), [
        '2 torrents errored',
        '2 torrents missing files',
      ]);
      expect(
        rows.map((row) => row.door),
        everyElement(const AttentionDoor.tab(ServiceTab.queue)),
      );
      expect(rows.map((row) => row.hash), everyElement(isNull));
      expect(rows.first.tone, StatusTone.warning);
    });

    test('stuck torrents are said as the downloads they are', () {
      final rows = qbittorrentFaultRows([
        _torrent(name: 'a', state: 'stalledDL'),
        _torrent(name: 'b', state: 'stalledDL'),
        _torrent(name: 'c', state: 'stalledDL'),
      ], now: now);

      expect(rows.single.headline, '3 downloads stuck');
      expect(rows.single.spoken, '3 downloads stuck, a, b, c');
    });
  });

  group('qbittorrentTransferRows', () {
    test('downloading first by progress, then seeding by upload rate', () {
      final rows = qbittorrentTransferRows([
        _torrent(name: 'seed-slow', state: 'uploading', upSpeed: 100),
        _torrent(name: 'dl-low', state: 'downloading', progress: 0.1),
        _torrent(name: 'seed-fast', state: 'uploading', upSpeed: 9000),
        _torrent(name: 'dl-high', state: 'downloading', progress: 0.9),
      ]);

      expect(rows.map((r) => r.name), [
        'dl-high',
        'dl-low',
        'seed-fast',
        'seed-slow',
      ]);
    });

    test('faults and paused torrents are absent by construction', () {
      // Nothing here appears both in the queue preview and in Needs attention.
      final rows = qbittorrentTransferRows([
        _torrent(name: 'stalled', state: 'stalledDL'),
        _torrent(name: 'errored', state: 'error'),
        _torrent(name: 'missing', state: 'missingFiles'),
        _torrent(name: 'paused', state: 'pausedDL'),
        _torrent(name: 'queued', state: 'queuedDL'),
      ]);

      expect(rows, isEmpty);
    });

    test('a downloading row carries category, size, rate and what is left', () {
      final rows = qbittorrentTransferRows([
        _torrent(
          name: 'Dune.Part.Two',
          state: 'downloading',
          category: 'movies',
          progress: 0.92,
          size: 15 * 1024 * 1024 * 1024,
          dlSpeed: 8 * 1024 * 1024,
          eta: 180,
        ),
      ]);

      final row = rows.single;
      expect(row.percent, '92%');
      expect(row.tone, StatusTone.info);
      expect(
        row.detail,
        'movies\u00A0· 15.0\u00A0GB\u00A0· 8.0\u00A0MB/\u2060s down\u00A0· 3\u00A0min left',
      );
    });

    test('a seeding row is GREEN: complete, not in flight', () {
      final rows = qbittorrentTransferRows([
        _torrent(
          name: 'Poor.Things',
          state: 'uploading',
          category: 'movies',
          progress: 1.0,
          size: 9 * 1024 * 1024 * 1024,
          upSpeed: 240 * 1024,
          ratio: 3.2,
        ),
      ]);

      expect(rows.single.tone, StatusTone.success);
      expect(
        rows.single.detail,
        'movies\u00A0· 9.0\u00A0GB\u00A0· 240\u00A0KB/\u2060s up\u00A0· ratio 3.20',
      );
    });

    test('an unknowable ETA is left unsaid, never rendered as ∞', () {
      // `etaFormatted` gives "∞" past qB's 8,640,000s sentinel, which a screen
      // reader says as "infinity" inside a sentence about a download.
      final rows = qbittorrentTransferRows([
        _torrent(name: 'x', state: 'downloading', eta: 8640000),
      ]);

      expect(rows.single.detail, isNot(contains('∞')));
      expect(rows.single.detail, isNot(contains('left')));
    });

    test('a magnet with no metadata reads `—` for its size, never 0 B', () {
      final rows = qbittorrentTransferRows([
        _torrent(name: 'magnet', state: 'metaDL', size: 0),
      ]);

      expect(rows.single.detail, contains('—'));
      expect(rows.single.detail, isNot(contains('0\u00A0B')));
    });

    test('the preview cap holds', () {
      final rows = qbittorrentTransferRows([
        for (var i = 0; i < 12; i++)
          _torrent(name: 'x$i', state: 'downloading', progress: i / 12),
      ]);
      expect(rows, hasLength(qbittorrentTransferPreviewLimit));
    });
  });

  group('qbittorrentQueueCounts', () {
    test('the census separates faults from the backlog it is not', () {
      final counts = qbittorrentQueueCounts([
        _torrent(state: 'downloading'),
        _torrent(state: 'metaDL'),
        _torrent(state: 'uploading'),
        _torrent(state: 'stalledUP'), // qB calls a seed with no peers stalledUP
        _torrent(state: 'stalledDL'),
        _torrent(state: 'pausedDL'),
        _torrent(state: 'stoppedUP'),
        _torrent(state: 'error'),
        _torrent(state: 'missingFiles'),
        _torrent(state: 'queuedDL'),
      ]);

      expect(counts.total, 10);
      expect(counts.downloading, 2);
      // stalledUP is a *seed*, not a stall: qB spells an idle seeder that way.
      expect(counts.seeding, 2);
      expect(counts.paused, 2);
      expect(counts.stalled, 1);
      expect(counts.errored, 2);
      expect(counts.faults, 3);
      expect(counts.active, 4);
    });
  });

  group('qbittorrentCategoryRows', () {
    test('largest first, with the torrent counts that go with them', () {
      final rows = qbittorrentCategoryRows([
        _torrent(category: 'tv', size: 10),
        _torrent(category: 'movies', size: 100),
        _torrent(category: 'tv', size: 20),
        _torrent(category: 'music', size: 5),
      ]);

      expect(rows.map((r) => r.name), ['movies', 'tv', 'music']);
      expect(rows.map((r) => r.count), [1, 2, 1]);
      expect(rows.map((r) => r.bytes), [100, 30, 5]);
      expect(rows.first.countLabel, '1 torrent');
      expect(rows[1].countLabel, '2 torrents');
    });

    test('uncategorised is kept, so the header total stays honest', () {
      final rows = qbittorrentCategoryRows([
        _torrent(category: '', size: 1000),
        _torrent(category: '   ', size: 1000),
        _torrent(category: 'movies', size: 1),
      ]);

      // Present: dropping it would make the section disagree with the count
      // the Queue tab shows two taps away…
      expect(rows.map((r) => r.name), ['movies', qbittorrentNoCategoryLabel]);
      // …and pinned last despite being by far the largest, because it is the
      // absence of a category rather than one.
      expect(rows.last.count, 2);
    });

    test('a 0-byte sentinel does not drag the category total', () {
      final rows = qbittorrentCategoryRows([
        _torrent(category: 'movies', size: 500),
        _torrent(category: 'movies', size: 0),
        _torrent(category: 'movies', size: -1),
      ]);

      expect(rows.single.bytes, 500);
      expect(rows.single.count, 3);
    });

    test('a category made only of metadata-less magnets reads —', () {
      final rows = qbittorrentCategoryRows([
        _torrent(category: 'new', size: 0),
      ]);
      expect(rows.single.sizeLabel, '—');
    });

    test('the row speaks one sentence', () {
      final rows = qbittorrentCategoryRows([
        _torrent(category: 'movies', size: 1024 * 1024),
      ]);
      expect(rows.single.spoken, 'movies, 1 torrent, 1.0\u00A0MB');
    });

    test('the cap holds', () {
      final rows = qbittorrentCategoryRows([
        for (var i = 0; i < 9; i++) _torrent(category: 'c$i', size: i + 1),
      ]);
      expect(rows, hasLength(qbittorrentCategoryLimit));
    });
  });

  group('qbittorrentGlobalLimitLabel: the OTHER 0 sentinel', () {
    test('0 is NO LIMIT globally, and must never print as a bare 0', () {
      // The per-torrent `dl_limit` reads 0 as "limit cleared" and -1 as
      // unlimited; `/transfer/info` is the inverse. Passing this through
      // `formatLimit` would print "0" over an uncapped gigabit link.
      expect(qbittorrentGlobalLimitLabel(0), 'no limit');
      expect(qbittorrentGlobalLimitLabel(-1), 'no limit');
    });

    test('a real limit renders as a rate', () {
      expect(
        qbittorrentGlobalLimitLabel(20 * 1024 * 1024),
        '20.0\u00A0MB/\u2060s',
      );
    });
  });

  group('qbittorrentSessionRatioLabel', () {
    test('nothing downloaded reads —, never 0.00 and never Infinity', () {
      expect(qbittorrentSessionRatioLabel(downloaded: 0, uploaded: 8000), '—');
      expect(qbittorrentSessionRatioLabel(downloaded: 0, uploaded: 0), '—');
    });

    test('a real ratio is two decimals', () {
      expect(
        qbittorrentSessionRatioLabel(downloaded: 100, uploaded: 214),
        '2.14',
      );
    });
  });

  group('qbittorrentSessionFacts', () {
    test('six facts when the server does not say its free space', () {
      final facts = qbittorrentSessionFacts(
        const TransferInfo(
          dlSpeed: 0,
          upSpeed: 0,
          dlInfoData: 1024 * 1024,
          upInfoData: 2 * 1024 * 1024,
          dlRateLimit: 0,
          upRateLimit: 5 * 1024 * 1024,
          altSpeedEnabled: false,
        ),
      );

      expect(facts.map((f) => f.label), [
        'Downloaded this session',
        'Uploaded this session',
        'Session ratio',
        'Download limit',
        'Upload limit',
        'Alternative limits',
      ]);
      expect(facts.map((f) => f.value), [
        '1.0\u00A0MB',
        '2.0\u00A0MB',
        '2.00',
        // The global sentinel, not a throttle to nothing.
        'no limit',
        '5.0\u00A0MB/\u2060s',
        'off',
      ]);
      // An old qBittorrent leaves free space out of its answer, and DHT nodes
      // are not drawn yet: both absent, rather than an em dash for a figure
      // that did not fail to answer.
      expect(facts.map((f) => f.label), isNot(contains('Free space')));
      expect(facts.map((f) => f.label), isNot(contains('DHT nodes')));
    });

    test('free space is the last fact, and a full disk reads 0 B', () {
      TransferInfo withFree(int bytes) => TransferInfo(
        dlSpeed: 0,
        upSpeed: 0,
        dlInfoData: 0,
        upInfoData: 0,
        dlRateLimit: 0,
        upRateLimit: 0,
        altSpeedEnabled: false,
        freeSpace: bytes,
      );

      final facts = qbittorrentSessionFacts(withFree(4 * 1024 * 1024 * 1024));
      expect(facts.last.label, 'Free space');
      expect(facts.last.value, '4.0\u00A0GB');
      // A full disk is the one figure a person most needs to read: never `—`.
      expect(qbittorrentSessionFacts(withFree(0)).last.value, '0\u00A0B');
    });

    test('a counter that answered 0 reads 0 B, never an em dash', () {
      // `formatSize` would print `—` here, and it would be right to for a
      // torrent size: a magnet with no metadata reports 0 and no torrent is
      // zero bytes. A session counter is not a size: a daemon restarted ten
      // minutes ago has genuinely moved nothing, and the server answered to
      // say so.
      expect(qbittorrentSessionTotalLabel(0), '0\u00A0B');
      expect(qbittorrentSessionTotalLabel(1024 * 1024), '1.0\u00A0MB');
      // Defensive only; no qB version is known to send one.
      expect(qbittorrentSessionTotalLabel(-1), '0\u00A0B');

      final facts = qbittorrentSessionFacts(
        const TransferInfo(
          dlSpeed: 0,
          upSpeed: 0,
          dlInfoData: 0,
          upInfoData: 0,
          dlRateLimit: 0,
          upRateLimit: 0,
          altSpeedEnabled: false,
        ),
      );

      expect(
        facts.firstWhere((f) => f.label == 'Downloaded this session').value,
        '0\u00A0B',
      );
      expect(
        facts.firstWhere((f) => f.label == 'Uploaded this session').value,
        '0\u00A0B',
      );
    });

    test('a fresh session reads `—` for its ratio, not 0.00', () {
      final facts = qbittorrentSessionFacts(
        const TransferInfo(
          dlSpeed: 0,
          upSpeed: 0,
          dlInfoData: 0,
          upInfoData: 0,
          dlRateLimit: 0,
          upRateLimit: 0,
          altSpeedEnabled: true,
        ),
      );

      final ratio = facts.firstWhere((f) => f.label == 'Session ratio');
      expect(ratio.value, '—');
      expect(ratio.spoken, 'Session ratio, —');
      // A bool that arrived is a bool, never an em dash.
      expect(
        facts.firstWhere((f) => f.label == 'Alternative limits').value,
        'on',
      );
    });
  });
}

// ─── Builder ────────────────────────────────────────────────────────────────

/// A torrent as `/torrents/info` would answer with it, defaulted to something
/// healthy so each test states only the field it is about.
Torrent _torrent({
  String name = 'torrent',
  String? hash,
  String state = 'downloading',
  double progress = 0.5,
  int size = 1024,
  String category = '',
  int dlSpeed = 0,
  int upSpeed = 0,
  int eta = 0,
  int seeders = 0,
  double ratio = 0,
  int lastActivity = 0,
}) {
  return Torrent(
    hash: hash ?? name,
    name: name,
    size: size,
    progress: progress,
    state: state,
    parsedState: TorrentState.fromString(state),
    dlSpeed: dlSpeed,
    upSpeed: upSpeed,
    eta: eta,
    category: category,
    tracker: '',
    tags: const [],
    ratio: ratio,
    addedOn: 0,
    completed: 0,
    leechers: 0,
    seeders: seeders,
    lastActivity: lastActivity,
  );
}

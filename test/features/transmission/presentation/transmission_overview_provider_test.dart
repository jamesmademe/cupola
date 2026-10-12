import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// A torrent, built through `fromJson` on purpose: it is the only constructor
/// production uses, it carries the sentinel defaults (`eta: -1`,
/// `uploadRatio: -1`) that the positional constructor would let a fixture skip
/// past, and it is the shape these window rules actually receive.
TransmissionTorrent _torrent({
  int id = 1,
  String name = 'A Torrent',
  int status = 6,
  int rateUpload = 0,
  int rateDownload = 0,
  int queuePosition = 0,
  bool isStalled = false,
  int error = 0,
  String errorString = '',
  List<String> labels = const [],
  int doneDate = 0,
  int totalSize = 1024 * 1024 * 1024,
  Object? uploadRatio = 2.6,
}) {
  return TransmissionTorrent.fromJson({
    'id': id,
    'hashString': 'hash$id',
    'name': name,
    'status': status,
    'percentDone': 1.0,
    'totalSize': totalSize,
    'rateDownload': rateDownload,
    'rateUpload': rateUpload,
    'queuePosition': queuePosition,
    'isStalled': isStalled,
    'error': error,
    'errorString': errorString,
    'labels': labels,
    'doneDate': doneDate,
    // Null-aware, so a null fixture omits the KEY, which is what makes
    // `fromJson` fall back to the `-1` "no ratio" sentinel rather than to 0.
    'uploadRatio': ?uploadRatio,
  });
}

/// Transmission reports `doneDate` in epoch **seconds**, so every fixture has to
/// divide: the one conversion a "finished today" rule gets wrong silently.
int _epochSeconds(DateTime when) => when.millisecondsSinceEpoch ~/ 1000;

/// A [TransmissionClient] that answers from a script instead of a daemon.
///
/// Extends the real client rather than reimplementing its interface, so the two
/// calls the free-space chain makes are the same two methods production calls;
/// the inherited transport is built but never reached, because every method the
/// chain touches is overridden here.
class _ScriptedClient extends TransmissionClient {
  _ScriptedClient({
    required this.scriptedSession,
    this.freeBytes,
    this.freeSpaceThrows = false,
  }) : super(url: 'http://daemon.test:9091');

  final TransmissionSession scriptedSession;

  /// Null is the daemon declining to answer; 0 is a disk with nothing left.
  final int? freeBytes;
  final bool freeSpaceThrows;

  /// Every path `free-space` was asked about. Empty means it was never called,
  /// which is itself a thing the chain promises.
  final List<String> freeSpaceCalls = [];

  @override
  Future<TransmissionSession> session() async => scriptedSession;

  @override
  Future<int?> freeSpace(String path) async {
    freeSpaceCalls.add(path);
    if (freeSpaceThrows) throw Exception('free-space refused');
    return freeBytes;
  }
}

ProviderContainer _container(_ScriptedClient client) {
  final container = ProviderContainer(
    overrides: [transmissionClientProvider.overrideWith((ref) => client)],
  );
  addTearDown(container.dispose);
  return container;
}

TransmissionSession _session({
  String downloadDir = '/downloads',
  String? incompleteDir,
  bool incompleteDirEnabled = false,
}) => TransmissionSession.fromJson({
  'version': '4.0.6',
  'rpc-version': 17,
  'download-dir': downloadDir,
  'incomplete-dir': ?incompleteDir,
  'incomplete-dir-enabled': incompleteDirEnabled,
  'alt-speed-enabled': false,
  'speed-limit-down': 4096,
  'speed-limit-down-enabled': true,
  'speed-limit-up': 1024,
  'speed-limit-up-enabled': false,
});

void main() {
  group('transmissionFocusRank', () {
    test('a fault outranks anything that is working', () {
      final stalled = _torrent(status: 4, isStalled: true);
      final downloading = _torrent(status: 4, rateDownload: 900);

      expect(
        transmissionFocusRank(stalled),
        lessThan(transmissionFocusRank(downloading)),
      );
    });

    test('a tracker warning is not a fault', () {
      // `error: 1` is Transmission's tracker *warning*: an announce hiccup on
      // an otherwise healthy torrent. Ranking it with the broken ones would put
      // routine noise at the top of the region forever.
      final warned = _torrent(status: 4, error: 1, errorString: 'announce');

      expect(
        transmissionFocusRank(warned),
        transmissionFocusRank(_torrent(status: 4)),
      );
    });

    test('an idle seed sorts behind one that is actually pushing bytes', () {
      expect(
        transmissionFocusRank(_torrent(status: 6, rateUpload: 120)),
        lessThan(transmissionFocusRank(_torrent(status: 6))),
      );
    });
  });

  group('transmissionTransferring', () {
    test('ranks faults, then transfers, then the rest', () {
      final rows = transmissionTransferring([
        _torrent(id: 1, name: 'idle seed', status: 6),
        _torrent(id: 2, name: 'downloading', status: 4, rateDownload: 900),
        _torrent(id: 3, name: 'stalled', status: 4, isStalled: true),
        _torrent(id: 4, name: 'active seed', status: 6, rateUpload: 120),
      ]);

      expect(rows.map((t) => t.name), [
        'stalled',
        'downloading',
        'active seed',
        'idle seed',
      ]);
    });

    test("keeps the daemon's own queue order inside a rank", () {
      final rows = transmissionTransferring([
        _torrent(id: 1, name: 'second', status: 4, queuePosition: 9),
        _torrent(id: 2, name: 'first', status: 4, queuePosition: 2),
      ]);

      expect(rows.map((t) => t.name), ['first', 'second']);
    });

    test('caps the sample without dropping the queue it came from', () {
      final rows = transmissionTransferring([
        for (var i = 0; i < 12; i++)
          _torrent(id: i, name: 'torrent $i', queuePosition: i),
      ], limit: 5);

      expect(rows, hasLength(5));
    });

    test('shows a seedbox with nothing downloading', () {
      // The region is a sample of the queue, not a filter on `isIncoming`: a
      // daemon that is only seeding is doing exactly its job, and an empty
      // "Transferring" would read as a fault.
      final rows = transmissionTransferring([
        _torrent(id: 1, status: 6, rateUpload: 90),
      ]);

      expect(rows, hasLength(1));
    });
  });

  group('transmissionTransferringSubtitle', () {
    test('a source that did not answer reads an em dash, never a zero', () {
      expect(transmissionTransferringSubtitle(null), '—');
    });

    test('counts downloading and seeding separately', () {
      expect(
        transmissionTransferringSubtitle([
          _torrent(id: 1, status: 4),
          _torrent(id: 2, status: 4),
          _torrent(id: 3, status: 6),
          // Stopped and queued belong to neither figure.
          _torrent(id: 4, status: 0),
          _torrent(id: 5, status: 3),
        ]),
        '2 downloading · 1 seeding',
      );
    });

    test('an empty queue is still two answered figures', () {
      expect(
        transmissionTransferringSubtitle(const []),
        '0 downloading · 0 seeding',
      );
    });
  });

  group('transmissionLabelTallies', () {
    test('counts every label a torrent wears', () {
      final tallies = transmissionLabelTallies([
        _torrent(id: 1, labels: ['movies', 'seed-forever']),
        _torrent(id: 2, labels: ['movies']),
        _torrent(id: 3, labels: ['tv']),
      ]);

      expect(tallies, const [
        TransmissionLabelTally(label: 'movies', count: 2),
        TransmissionLabelTally(label: 'seed-forever', count: 1),
        TransmissionLabelTally(label: 'tv', count: 1),
      ]);
    });

    test('ties break alphabetically, so two polls do not reshuffle', () {
      final first = transmissionLabelTallies([
        _torrent(id: 1, labels: ['zeta']),
        _torrent(id: 2, labels: ['alpha']),
      ]);
      final second = transmissionLabelTallies([
        _torrent(id: 2, labels: ['alpha']),
        _torrent(id: 1, labels: ['zeta']),
      ]);

      expect(first.map((t) => t.label), ['alpha', 'zeta']);
      expect(second.map((t) => t.label), first.map((t) => t.label));
    });

    test('a whitespace-only label is dropped, not tallied as a blank row', () {
      final tallies = transmissionLabelTallies([
        _torrent(id: 1, labels: ['  ', '']),
      ]);

      expect(tallies, isEmpty);
    });

    test('an untagged daemon has no labels rather than one empty one', () {
      expect(transmissionLabelTallies([_torrent(id: 1)]), isEmpty);
    });

    test('speaks the count as a noun, not as a bare numeral', () {
      const one = TransmissionLabelTally(label: 'tv', count: 1);
      const many = TransmissionLabelTally(label: 'movies', count: 10);

      expect(one.spoken, 'tv, 1 torrent');
      expect(many.spoken, 'movies, 10 torrents');
    });
  });

  group('transmissionLimitLabel', () {
    test('a stored limit that is switched off reads Not limited', () {
      // Transmission keeps the number while the flag is false; printing it
      // would claim a ceiling that is not being enforced.
      expect(transmissionLimitLabel(4096, enabled: false), 'Not limited');
    });

    test('an enforced limit prints the API unit it was set in', () {
      expect(transmissionLimitLabel(4096, enabled: true), '4096\u00A0KB/s');
    });

    test('an enforced zero says what it does', () {
      expect(transmissionLimitLabel(0, enabled: true), 'Stopped (0\u00A0KB/s)');
    });
  });

  group('transmissionSessionFacts', () {
    TransmissionSession session({
      bool alt = false,
      String downloadDir = '/downloads',
    }) => TransmissionSession.fromJson({
      'version': '4.0.6',
      'rpc-version': 17,
      'download-dir': downloadDir,
      'alt-speed-enabled': alt,
      'speed-limit-down': 4096,
      'speed-limit-down-enabled': true,
      'speed-limit-up': 1024,
      'speed-limit-up-enabled': false,
    });

    test('slow mode is informational, never a fault', () {
      final facts = transmissionSessionFacts(session(alt: true));
      final slowMode = facts.first;

      expect(slowMode.label, 'Slow mode');
      expect(slowMode.value, 'On');
      // The single most common way the tone rule breaks: a throttle the user
      // switched on themselves painted amber.
      expect(slowMode.tone, StatusTone.info);
      expect(slowMode.tone, isNot(StatusTone.warning));
    });

    test('slow mode off is neutral and explains what does apply', () {
      final slowMode = transmissionSessionFacts(session()).first;

      expect(slowMode.value, 'Off');
      expect(slowMode.tone, StatusTone.neutral);
      expect(slowMode.detail, 'the global limits apply');
    });

    test('free space nobody could measure reads an em dash, never 0 B', () {
      final free = transmissionSessionFacts(
        session(),
      ).firstWhere((f) => f.label == 'Free space');

      expect(free.value, '—');
      expect(free.value, isNot(contains('0')));
      // The path still shows: a free-space figure with no path attached is a
      // number about an unnamed disk, and that stays true when the figure is
      // missing.
      expect(free.detail, '/downloads');
    });

    test('free space that was measured prints a size', () {
      final free = transmissionSessionFacts(
        session(),
        freeSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
      ).firstWhere((f) => f.label == 'Free space');

      expect(free.value, '2.0\u00A0TB');
    });

    test('a daemon that named no download directory says so', () {
      final free = transmissionSessionFacts(
        session(downloadDir: '   '),
      ).firstWhere((f) => f.label == 'Free space');

      expect(free.detail, 'download directory unknown');
    });

    test('each row speaks as one sentence', () {
      final slowMode = transmissionSessionFacts(session(alt: true)).first;

      expect(slowMode.spoken, 'Slow mode, On, alternative limits are in force');
    });
  });

  group('the Finished today tone', () {
    // The region reads the app's one mapping of Transmission's eight states:
    // `transmissionTorrentTone`, exercised state by state in
    // test/features/transmission/domain/transmission_tone_test.dart. What these
    // check is that this region reaches for it, because it used to carry a
    // second switch that guarded two arms and fell through to green.
    final now = DateTime(2026, 9, 16, 14, 30);
    final doneToday = _epochSeconds(DateTime(2026, 9, 16, 9));

    StatusTone toneOf(int status) => transmissionFinishedToday([
      _torrent(status: status, doneDate: doneToday),
    ], now: now).single.tone;

    test('a torrent stopped on purpose is backlog, not a fault', () {
      expect(toneOf(0), StatusTone.neutral);
    });

    test('a seeding torrent is complete, so it reads green', () {
      expect(toneOf(6), StatusTone.success);
    });

    test('a finished torrent waiting to seed has not finished seeding', () {
      // `status: 5` is seedWait. Green here contradicted the same torrent's
      // chip in Transferring, two regions above, on the same page; both read
      // the queue's blue, in line to seed.
      expect(toneOf(5), StatusTone.info);
    });

    test('one being re-verified is work in flight', () {
      expect(toneOf(2), StatusTone.info);
    });

    test('a status code this app has no name for claims nothing', () {
      expect(toneOf(99), StatusTone.neutral);
    });

    test('a local error is a fault', () {
      final item = transmissionFinishedToday([
        _torrent(
          status: 6,
          error: 3,
          errorString: 'No data found',
          doneDate: doneToday,
        ),
      ], now: now).single;

      expect(item.tone, StatusTone.warning);
    });
  });

  group('transmissionFinishedToday', () {
    final now = DateTime(2026, 9, 16, 14, 30);

    test('takes the local calendar day, not a rolling 24 hours', () {
      final items = transmissionFinishedToday([
        _torrent(
          id: 1,
          name: 'this morning',
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 2)),
        ),
        // Twenty minutes older than "this morning" is irrelevant: the heading
        // says today, and a heading is a promise.
        _torrent(
          id: 2,
          name: 'last night',
          doneDate: _epochSeconds(DateTime(2026, 9, 15, 23, 50)),
        ),
      ], now: now);

      expect(items.map((i) => i.name), ['this morning']);
    });

    test('a torrent that never finished is not 1 January 1970', () {
      // `doneDate: 0` is Transmission's "never", and left unguarded it parses
      // to the epoch, which on any day but one is simply "not today", so the
      // bug hides until someone reads the list on a slow day.
      final items = transmissionFinishedToday([
        _torrent(id: 1, doneDate: 0),
      ], now: now);

      expect(items, isEmpty);
    });

    test('the epoch itself is only today on 1 January 1970', () {
      final items = transmissionFinishedToday([
        _torrent(id: 1, doneDate: 0),
      ], now: DateTime.fromMillisecondsSinceEpoch(0).toLocal());

      // Guarded on `<= 0` rather than on the date, so even here nothing leaks.
      expect(items, isEmpty);
    });

    test('newest first, capped', () {
      final items = transmissionFinishedToday(
        [
          _torrent(
            id: 1,
            name: 'oldest',
            doneDate: _epochSeconds(DateTime(2026, 9, 16, 1)),
          ),
          _torrent(
            id: 2,
            name: 'newest',
            doneDate: _epochSeconds(DateTime(2026, 9, 16, 13)),
          ),
          _torrent(
            id: 3,
            name: 'middle',
            doneDate: _epochSeconds(DateTime(2026, 9, 16, 9)),
          ),
        ],
        now: now,
        limit: 2,
      );

      expect(items.map((i) => i.name), ['newest', 'middle']);
    });

    test('the detail line is size, age and current state', () {
      final items = transmissionFinishedToday([
        _torrent(
          id: 1,
          status: 6,
          totalSize: 1024 * 1024 * 1024,
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 12, 30)),
        ),
      ], now: now);

      expect(items.single.detail, '1.0\u00A0GB · 2\u00A0h ago · seeding');
    });

    test('a ratio Transmission did not report reads an em dash', () {
      final items = transmissionFinishedToday([
        _torrent(
          id: 1,
          uploadRatio: null,
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 12)),
        ),
      ], now: now);

      expect(items.single.ratioLabel, '—');
    });

    test('a reported ratio is named, not left as a bare number', () {
      final items = transmissionFinishedToday([
        _torrent(
          id: 1,
          uploadRatio: 2.6,
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 12)),
        ),
      ], now: now);

      expect(items.single.ratioLabel, 'ratio 2.60');
    });

    test('an infinite ratio is a ratio, never the unknown dash', () {
      // `-2`, `TR_RATIO_INF`: sent and never received, a torrent added over
      // data already on disk.
      final items = transmissionFinishedToday([
        _torrent(
          id: 1,
          uploadRatio: -2,
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 12)),
        ),
      ], now: now);

      expect(items.single.ratioLabel, 'ratio ∞');
    });

    test('the row speaks as one sentence, with the dots turned into commas', () {
      final item = transmissionFinishedToday([
        _torrent(
          id: 1,
          name: 'Andor.S02E02.1080p.WEB-DL',
          status: 6,
          totalSize: 1024 * 1024 * 1024,
          uploadRatio: 2.6,
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 12, 30)),
        ),
      ], now: now).single;

      expect(
        item.spoken,
        'Andor.S02E02.1080p.WEB-DL, 1.0\u00A0GB, 2\u00A0h ago, seeding, ratio 2.60',
      );
      // `·` is decoration: iOS reads it as "middle dot" or drops it depending
      // on the user's punctuation verbosity, and neither is what the row meant.
      expect(item.spoken, isNot(contains('·')));
    });

    test("a faulted torrent speaks the daemon's own sentence", () {
      final item = transmissionFinishedToday([
        _torrent(
          id: 1,
          status: 6,
          error: 3,
          errorString: 'No data found',
          doneDate: _epochSeconds(DateTime(2026, 9, 16, 14)),
        ),
      ], now: now).single;

      expect(item.detail, contains('no data found'));
      expect(item.tone, StatusTone.warning);
    });
  });

  group('the free-space chain', () {
    test('asks free-space for the path session-get reported', () async {
      final client = _ScriptedClient(
        scriptedSession: _session(downloadDir: '/mnt/pool/downloads'),
        freeBytes: 2 * 1024 * 1024 * 1024 * 1024,
      );
      final container = _container(client);

      final bytes = await container.read(transmissionFreeSpaceProvider.future);

      // The ordering is the whole reason this is two calls: `free-space` takes
      // a path, and the only path the app knows comes out of `session-get`.
      expect(client.freeSpaceCalls, ['/mnt/pool/downloads']);
      expect(bytes, 2 * 1024 * 1024 * 1024 * 1024);

      final facts = await container.read(
        transmissionSessionFactsProvider.future,
      );
      expect(
        facts.firstWhere((f) => f.label == 'Free space').value,
        '2.0\u00A0TB',
      );
    });

    test('a daemon that named no directory is never asked', () async {
      final client = _ScriptedClient(
        scriptedSession: _session(downloadDir: '  '),
      );
      final container = _container(client);

      expect(
        await container.read(transmissionFreeSpaceProvider.future),
        isNull,
      );
      // Not merely null: the call is not made at all. Asking `free-space` for
      // an empty path is a request the daemon answers with an error.
      expect(client.freeSpaceCalls, isEmpty);
    });

    test('a daemon that did not answer costs the figure, not the row', () async {
      // Null, never 0: the client now distinguishes an unanswered `size-bytes`
      // from a measured one, so this layer no longer has to throw away the
      // only reading that matters to fake that distinction.
      final container = _container(
        _ScriptedClient(scriptedSession: _session(), freeBytes: null),
      );

      expect(
        await container.read(transmissionFreeSpaceProvider.future),
        isNull,
      );

      final facts = await container.read(
        transmissionSessionFactsProvider.future,
      );
      final free = facts.firstWhere((f) => f.label == 'Free space');
      expect(free.value, '—');
      expect(free.tone, StatusTone.neutral);
    });

    test('a full disk says so instead of reading as silence', () async {
      // The defect: `freeSpace` collapsed a missing key to 0 and the provider
      // folded every 0 back to null to recover the missing case, so the one
      // reading a user needs before starting a grab rendered as an em dash,
      // indistinguishable from a daemon that said nothing.
      final container = _container(
        _ScriptedClient(scriptedSession: _session(), freeBytes: 0),
      );

      expect(await container.read(transmissionFreeSpaceProvider.future), 0);

      final facts = await container.read(
        transmissionSessionFactsProvider.future,
      );
      final free = facts.firstWhere((f) => f.label == 'Free space');
      expect(free.value, '0\u00A0B');
      // A fault, and the only one this region can carry: the disk stopped
      // being able to take a download, which is not a setting anybody chose.
      expect(free.tone, StatusTone.warning);
    });

    test('measures the incomplete directory when one is in force', () async {
      // Transmission downloads into `incomplete-dir` and only moves the file
      // to `download-dir` when it finishes, so on that setup the free space at
      // `download-dir` describes a volume the user is not filling.
      final client = _ScriptedClient(
        scriptedSession: _session(
          downloadDir: '/mnt/media/complete',
          incompleteDir: '/mnt/fast/incomplete',
          incompleteDirEnabled: true,
        ),
        freeBytes: 512 * 1024 * 1024 * 1024,
      );
      final container = _container(client);

      await container.read(transmissionFreeSpaceProvider.future);
      expect(client.freeSpaceCalls, ['/mnt/fast/incomplete']);

      final facts = await container.read(
        transmissionSessionFactsProvider.future,
      );
      final free = facts.firstWhere((f) => f.label == 'Free space');
      // The row names the path it measured, and which directory that is: the
      // figure and its subject have to be the same volume, or the row answers
      // the wrong question while looking right.
      expect(free.detail, '/mnt/fast/incomplete · incomplete directory');
    });

    test('ignores an incomplete directory that is switched off', () async {
      // Transmission keeps the stored path while the flag is false, exactly as
      // it keeps a speed limit that is not in force.
      final client = _ScriptedClient(
        scriptedSession: _session(
          downloadDir: '/mnt/media/complete',
          incompleteDir: '/mnt/fast/incomplete',
        ),
        freeBytes: 1024,
      );
      final container = _container(client);

      await container.read(transmissionFreeSpaceProvider.future);
      expect(client.freeSpaceCalls, ['/mnt/media/complete']);
    });

    test('falls back when the flag is on and the path is empty', () async {
      final client = _ScriptedClient(
        scriptedSession: _session(
          downloadDir: '/mnt/media/complete',
          incompleteDir: '   ',
          incompleteDirEnabled: true,
        ),
        freeBytes: 1024,
      );
      final container = _container(client);

      await container.read(transmissionFreeSpaceProvider.future);
      expect(client.freeSpaceCalls, ['/mnt/media/complete']);
    });

    test('a refused free-space costs the figure, not the region', () async {
      final container = _container(
        _ScriptedClient(scriptedSession: _session(), freeSpaceThrows: true),
      );

      final facts = await container.read(
        transmissionSessionFactsProvider.future,
      );

      // Three good rows survive the fourth call failing, taking the region
      // down to report a missing figure is the trade the em-dash rule refuses.
      expect(facts.map((f) => f.label), [
        'Slow mode',
        'Download limit',
        'Upload limit',
        'Free space',
      ]);
      expect(facts.firstWhere((f) => f.label == 'Free space').value, '—');
      // The path still shows: a free-space figure with no path attached is a
      // number about an unnamed disk, and that stays true when it is missing.
      expect(facts.last.detail, '/downloads');
    });
  });
}

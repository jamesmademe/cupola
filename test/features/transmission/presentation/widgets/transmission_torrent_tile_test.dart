import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/widgets/transmission_torrent_tile.dart';

TransmissionTorrent _torrent({
  int status = 4,
  double percentDone = 0.42,
  int rateDownload = 1024,
  int rateUpload = 256,
  bool isStalled = false,
  int error = 0,
  String errorString = '',
}) {
  return TransmissionTorrent.fromJson({
    'id': 7,
    'name': 'Ubuntu 24.04 LTS',
    'status': status,
    'percentDone': percentDone,
    'totalSize': 1024 * 1024 * 1024,
    'sizeWhenDone': 1024 * 1024 * 1024,
    'leftUntilDone': 512 * 1024 * 1024,
    'rateDownload': rateDownload,
    'rateUpload': rateUpload,
    'eta': 3600,
    'uploadRatio': 1.5,
    'error': error,
    'errorString': errorString,
    'isStalled': isStalled,
  });
}

Future<DownloadQueueTile> _plateFor(
  WidgetTester tester,
  TransmissionTorrent torrent, {
  Widget? actions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: ListView(
          children: [
            TransmissionTorrentTile(torrent: torrent, actions: actions),
          ],
        ),
      ),
    ),
  );
  return tester.widget<DownloadQueueTile>(find.byType(DownloadQueueTile));
}

void main() {
  group('TransmissionTorrentTile', () {
    // The migration itself: Transmission was the last client still drawing its
    // own row. A fourth private copy is what the shared plate exists to stop,
    // and only mounting it catches the Material assertion that blanked the
    // qBittorrent list when its copy passed `shape` and `borderRadius` together.
    testWidgets('draws on the shared plate, without tripping an assertion', (
      tester,
    ) async {
      await _plateFor(tester, _torrent());

      expect(tester.takeException(), isNull);
      expect(find.byType(DownloadQueueTile), findsOneWidget);
    });

    // The tone rule, on the state where it is least intuitive. Red in this app
    // means exactly one thing: a connection that did not answer, and a
    // torrent the daemon reports as stalled or errored is the opposite of
    // that: it answered, and what it said is that this transfer is stuck. That
    // is a fault, and faults are amber.
    testWidgets('a stalled or errored torrent is amber, never red', (
      tester,
    ) async {
      final stalled = await _plateFor(
        tester,
        _torrent(isStalled: true, status: 4),
      );
      expect(stalled.statusTone, StatusTone.warning);
      expect(stalled.statusLabel, 'Stuck');

      final errored = await _plateFor(
        tester,
        _torrent(error: 3, errorString: 'Tracker gone'),
      );
      expect(errored.statusTone, StatusTone.warning);
      // The daemon's own words, on the chip. They used to be a coloured prefix
      // glued onto the front of the subtitle, where nothing could read them as
      // a state.
      expect(errored.statusLabel, 'Tracker gone');
    });

    // Seeding is the one state that means "this one is done"; the queues and a
    // deliberate stop are the resting state of a torrent client and must not
    // compete for attention with the states that are actually wrong.
    testWidgets('the calm states are green, blue and neutral', (tester) async {
      const expected = {
        6: StatusTone.success, // seed
        4: StatusTone.info, // download
        2: StatusTone.info, // check
        0: StatusTone.neutral, // stopped
        // The three queues: in line, blue as queued is everywhere.
        3: StatusTone.info, // downloadWait
        5: StatusTone.info, // seedWait
        1: StatusTone.info, // checkWait
      };
      for (final entry in expected.entries) {
        final plate = await _plateFor(tester, _torrent(status: entry.key));
        expect(plate.statusTone, entry.value, reason: 'status ${entry.key}');
      }
    });

    // "No progress" and "zero progress" are different facts. A queued torrent
    // has not started, and a 0% bar under it reads as a transfer that is stuck
    // rather than one that has not begun, so the plate is handed null and
    // draws nothing, instead of the row deciding by omitting a widget.
    testWidgets('a torrent with nothing to show gets no bar', (tester) async {
      expect((await _plateFor(tester, _torrent(status: 3))).progress, isNull);
      expect(
        (await _plateFor(tester, _torrent(status: 6, percentDone: 1))).progress,
        isNull,
      );
      expect(
        (await _plateFor(
          tester,
          _torrent(error: 3, errorString: 'x'),
        )).progress,
        isNull,
      );
      expect(
        (await _plateFor(tester, _torrent(status: 4))).progress,
        closeTo(0.42, 0.001),
      );
    });

    // The rates are the only figures on the row whose meaning is carried by a
    // glyph, and screen readers disagree about arrows: some skip them, some
    // name the character. Neither reading is "downloading at".
    testWidgets('the transfer arrows are spelt out for a screen reader', (
      tester,
    ) async {
      final plate = await _plateFor(tester, _torrent());

      expect(plate.metrics, hasLength(2));
      expect(plate.metrics.first.spoken, startsWith('downloading at '));
      expect(plate.metrics.last.spoken, startsWith('uploading at '));

      // A rate of zero is dropped rather than printed: "↓ 0 B/s" is a figure
      // about nothing on a row that already says the torrent is stopped.
      final idle = await _plateFor(
        tester,
        _torrent(status: 0, rateDownload: 0, rateUpload: 0),
      );
      expect(idle.metrics, isEmpty);
    });

    // The commands stay a slot the screen fills, and the plate keeps them on the
    // screen reader's path: the row publishes one container with the menu as an
    // explicit child, never an `ExcludeSemantics` that would drop it.
    testWidgets('the row menu reaches the screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await _plateFor(
        tester,
        _torrent(),
        actions: IconButton(
          tooltip: 'Torrent actions',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {},
        ),
      );

      // A node of its own, inside the row's labelled container. If the plate
      // ever reached for `ExcludeSemantics`, or the row published no container
      // and merged everything, this would resolve to an ancestor with no
      // tooltip, and the only per-torrent commands in the app would be
      // unreachable without sight.
      expect(
        tester.getSemantics(find.byType(IconButton)).tooltip,
        'Torrent actions',
      );
      handle.dispose();
    });
  });
}

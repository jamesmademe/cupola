import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_tile.dart';

Torrent _torrent({
  String name = 'Ubuntu 24.04 LTS',
  String state = 'downloading',
  int dlSpeed = 1024,
  int upSpeed = 256,
  double progress = 0.42,
}) {
  return Torrent.fromJson({
    'hash': 'abc123',
    'name': name,
    'size': 1024 * 1024 * 1024,
    'progress': progress,
    'state': state,
    'dlspeed': dlSpeed,
    'upspeed': upSpeed,
    'eta': 3600,
    'category': 'linux',
    'tracker': 'https://tracker.example.com/announce',
    'tags': ['iso'],
    'ratio': 1.5,
    'added_on': 1700000000,
    'completed': 512,
    'num_leechs': 3,
    'num_seeds': 7,
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.lightTheme(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

void main() {
  group('TorrentTile', () {
    // Regression guard for the P0 found in QA: the tile passed both
    // `borderRadius` and `shape` to Material, which trips
    // `!(shape != null && borderRadius != null)` and blanked the entire
    // qBittorrent list. Only mounting the widget catches a build assertion —
    // the provider tests never did.
    testWidgets('builds without tripping a Material assertion', (tester) async {
      await _pump(tester, TorrentTile(torrent: _torrent()));

      expect(tester.takeException(), isNull);
      expect(find.byType(TorrentTile), findsOneWidget);
      expect(find.text('Ubuntu 24.04 LTS'), findsOneWidget);
    });

    // The rule this whole file now exists to hold: **one plate, four clients.**
    // qBittorrent carried a private second implementation of
    // `DownloadQueueTile` — the precise duplication that widget was written to
    // prevent — and it had drifted into its own radius, its own padding and no
    // semantics container at all. A tile that stops rendering through the
    // shared plate is a third copy in the making, whatever it looks like.
    testWidgets('renders through the shared queue plate', (tester) async {
      await _pump(tester, TorrentTile(torrent: _torrent()));

      expect(find.byType(DownloadQueueTile), findsOneWidget);
    });

    testWidgets('builds selected, in both themes', (tester) async {
      for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
        await _pump(
          tester,
          TorrentTile(torrent: _torrent(), selected: true),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('builds across every torrent state', (tester) async {
      const states = [
        'downloading',
        'stalledDL',
        'uploading',
        'stalledUP',
        'pausedDL',
        'stoppedDL',
        'queuedDL',
        'checkingDL',
        'error',
        'missingFiles',
        'moving',
      ];
      for (final state in states) {
        await _pump(
          tester,
          TorrentTile(torrent: _torrent(state: state, dlSpeed: 0, upSpeed: 0)),
        );
        expect(tester.takeException(), isNull, reason: state);
      }
    });

    testWidgets('forwards tap and long-press', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await _pump(
        tester,
        TorrentTile(
          torrent: _torrent(),
          onTap: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );

      await tester.tap(find.byType(TorrentTile));
      await tester.pumpAndSettle();
      expect(taps, 1);

      await tester.longPress(find.byType(TorrentTile));
      await tester.pumpAndSettle();
      expect(longPresses, 1);
    });

    // The tone rule, on the one state where it is least intuitive. Red in this
    // app means exactly one thing — a connection that did not answer — and a
    // torrent qBittorrent reports as errored is the opposite of that: the
    // client answered, and told us the transfer is stuck. That is a fault, and
    // faults are amber. The private tile painted `colorScheme.error` here.
    testWidgets('paints a stuck torrent amber, never red', (tester) async {
      for (final state in ['error', 'stalledDL']) {
        await _pump(tester, TorrentTile(torrent: _torrent(state: state)));

        final plate = tester.widget<DownloadQueueTile>(
          find.byType(DownloadQueueTile),
        );
        expect(plate.statusTone, StatusTone.warning, reason: state);
      }
    });

    // Seeding is the one qBittorrent state that means "this one is done", and
    // queued/paused are backlog — the resting state of every torrent client,
    // which must not compete for attention with the two states that are wrong.
    testWidgets('tones the calm states green and neutral', (tester) async {
      const expected = {
        'uploading': StatusTone.success,
        'stalledUP': StatusTone.success,
        'queuedDL': StatusTone.neutral,
        'pausedDL': StatusTone.neutral,
        'downloading': StatusTone.info,
      };
      for (final entry in expected.entries) {
        await _pump(tester, TorrentTile(torrent: _torrent(state: entry.key)));

        final plate = tester.widget<DownloadQueueTile>(
          find.byType(DownloadQueueTile),
        );
        expect(plate.statusTone, entry.value, reason: entry.key);
      }
    });

    // A torrent that has not started has *no* progress, which is a different
    // fact from zero progress: a 0% bar under a queued row reads as a transfer
    // that is stuck rather than one that has not begun. The plate says this in
    // the value, so a null here is the assertion.
    testWidgets('draws no bar for a torrent that has not started', (
      tester,
    ) async {
      for (final state in ['queuedDL', 'queuedUP', 'error']) {
        await _pump(tester, TorrentTile(torrent: _torrent(state: state)));

        final plate = tester.widget<DownloadQueueTile>(
          find.byType(DownloadQueueTile),
        );
        expect(plate.progress, isNull, reason: state);
      }

      await _pump(tester, TorrentTile(torrent: _torrent()));
      expect(
        tester
            .widget<DownloadQueueTile>(find.byType(DownloadQueueTile))
            .progress,
        closeTo(0.42, 0.001),
      );
    });

    // The row used to speak as four unrelated fragments, because the private
    // tile declared no semantics container — and its two transfer rates were
    // carried by an arrow glyph that screen readers either skip or read as the
    // name of the character. A rate a sighted user can see and a screen-reader
    // user cannot is a missing feature, not a missing flourish.
    testWidgets('speaks as one row, arrows spelled out', (tester) async {
      final handle = tester.ensureSemantics();

      await _pump(tester, TorrentTile(torrent: _torrent()));

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Ubuntu 24\.04 LTS, Downloading, 42 percent, .*'
            r'downloading at .*, uploading at ',
          ),
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    // Long-press is selection (decision 28), and the *container* node is what
    // carries both gestures: one row is one thing a screen reader can act on.
    // An InkWell publishing its own unlabelled node inside the labelled one is
    // how a two-finger swipe ends up having to find the inner one.
    testWidgets('puts tap and long-press on the row\'s own node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await _pump(
        tester,
        TorrentTile(
          torrent: _torrent(),
          selected: true,
          onTap: () {},
          onLongPress: () {},
        ),
      );

      final data = tester
          .getSemantics(find.byType(DownloadQueueTile))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(data.flagsCollection.isSelected, Tristate.isTrue);

      handle.dispose();
    });

    testWidgets('survives a long name on a narrow screen', (tester) async {
      await _pump(
        tester,
        TorrentTile(torrent: _torrent(name: 'A' * 240)),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large text scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: ListView(children: [TorrentTile(torrent: _torrent())]),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

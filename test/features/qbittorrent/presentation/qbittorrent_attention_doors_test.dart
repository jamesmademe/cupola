/// qBittorrent's Needs attention leads where the fault is fixed: one stuck
/// torrent opens its own download page and can be asked for peers again, the
/// several of a state are one row that opens the Queue tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _gb = 1024 * 1024 * 1024;

WorldDownload _stuck(String hash, String release) => WorldDownload(
  id: hash,
  release: release,
  client: 'qbittorrent',
  state: DownloadState.stuck,
  progress: 0.3,
  size: _gb,
);

Future<(ProfileHarness, OverviewShell)> _pump(
  WidgetTester tester, {
  List<WorldDownload> extra = const [],
}) async {
  final harness = await ProfileHarness.start(Profiles.p1.withDownloads(extra));
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = OverviewShell(
    ServiceKey.qbittorrent,
    const QbittorrentOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: harness.overrides, child: shell.app),
  );
  await harness.settle(tester);
  return (harness, shell);
}

void main() {
  testWidgets('P1: the stuck torrent opens its own download page, and can be '
      'asked for peers again from its row', (tester) async {
    final (harness, shell) = await _pump(tester);

    final row = find.textContaining('Stuck\u00A0· Big.Buck.Bunny');
    expect(row, findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp(r'^Stuck, Big\.Buck\.Bunny')),
      containsSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens this download',
      ),
    );
    expect(
      find.semantics.byHint(
        'asks the trackers again for Big.Buck.Bunny.2008.1080p.BluRay',
      ),
      containsSemantics(
        label: 'Look for peers again',
        isButton: true,
        hasTapAction: true,
      ),
    );

    // The verb is qBittorrent's own call, for that torrent's hash.
    await tester.tap(find.text('Look for peers again'));
    await harness.settle(tester);
    final reannounce = [
      for (final request in harness.network.requestsTo(WorldIds.qbittorrent))
        if (request.path == '/api/v2/torrents/reannounce') request,
    ];
    expect(reannounce, hasLength(1));
    expect(reannounce.single.form['hashes'], WorldDownloads.bigBuckBunny.id);
    expect(find.text('Asked the trackers for more peers'), findsOneWidget);
    expect(shell.tab, ServiceTab.overview);

    // The row's body, not the verb, is the way to the download's page, on
    // the connection that listed it.
    await tester.tap(row);
    await harness.settle(tester);
    expect(
      shell.location,
      '/activity/download?i=${WorldIds.qbittorrent}'
      '&id=${WorldDownloads.bigBuckBunny.id}',
    );
    expect(
      harness.network
          .requestsTo(WorldIds.qbittorrent)
          .where((request) => request.path == '/api/v2/torrents/reannounce'),
      hasLength(1),
      reason: 'opening the page does not ask again',
    );

    await harness.unmount(tester);
  });

  testWidgets('P1: three stuck torrents are one row that opens the Queue tab, '
      'and no verb', (tester) async {
    final (harness, shell) = await _pump(
      tester,
      extra: [
        _stuck('a1f0c3d4e5f60718293a4b5c6d7e8f9012345611', 'Alpha.Release'),
        _stuck('a1f0c3d4e5f60718293a4b5c6d7e8f9012345612', 'Bravo.Release'),
      ],
    );

    expect(find.text('3 downloads stuck'), findsOneWidget);
    expect(find.textContaining('Stuck\u00A0·'), findsNothing);
    expect(find.text('Look for peers again'), findsNothing);
    expect(
      find.semantics.byLabel(RegExp(r'^3 downloads stuck, ')),
      containsSemantics(
        isButton: true,
        hint: 'opens the qBittorrent Queue tab',
      ),
    );
    // The header counts the torrents, not the one row.
    expect(
      find.semantics.byLabel(RegExp(r'^Needs attention, 3')),
      findsWidgets,
    );

    await tester.tap(find.text('3 downloads stuck'));
    await harness.settle(tester);
    expect(shell.tab, ServiceTab.queue);

    await harness.unmount(tester);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/torrent_detail_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('a torrent qBittorrent no longer has keeps the page frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
          ),
          qbittorrentTorrentsProvider.overrideWith((ref, hash) async => []),
          torrentDetailPollingProvider.overrideWith((ref, hash) {}),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const TorrentDetailScreen(hash: 'abc'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The bar, so there is a way back, and words rather than a bare line.
    expect(find.text('Torrent'), findsOneWidget);
    expect(find.text('This torrent is not in qBittorrent'), findsOneWidget);
  });
}

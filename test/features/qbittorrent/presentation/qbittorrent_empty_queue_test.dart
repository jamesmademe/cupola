import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

/// An empty list is one line where the rows would start, as every other
/// client's empty queue reads, and a filter that hides everything says so
/// instead of claiming the client holds nothing.
void main() {
  Future<void> pump(WidgetTester tester, {TorrentFilter? filter}) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(qbittorrentUrl: 'http://qb.test'),
          ),
          torrentsProvider.overrideWith((ref) async => const <Torrent>[]),
          allTorrentsProvider.overrideWith((ref) async => const <Torrent>[]),
          torrentPollingProvider.overrideWith((ref) {}),
          serviceKpiProvider.overrideWith(
            (ref, service) async => const <ServiceKpi>[],
          ),
          if (filter != null)
            torrentFilterProvider.overrideWith((ref) => filter),
        ],
        child: const MaterialApp(home: QbittorrentScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no torrents at all reads as an empty client', (tester) async {
    await pump(tester);

    expect(find.text('No torrents'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('a filter that hides everything says so', (tester) async {
    await pump(tester, filter: TorrentFilter.seeding);

    expect(find.text('No matching torrents'), findsOneWidget);
    expect(find.text('No torrents'), findsNothing);
  });
}

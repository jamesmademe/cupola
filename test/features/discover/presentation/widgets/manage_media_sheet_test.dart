import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';

import 'package:cupola/features/discover/presentation/widgets/manage_media_sheet.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../../test_helpers/fake_services.dart';
import '../../../../test_helpers/settings_scope.dart';

void main() {
  group('ManageMediaSheet', () {
    testWidgets('remove action is a silent no-op when seerr id is missing', (
      tester,
    ) async {
      var onDataChangedCount = 0;

      await _pumpSheet(
        tester,
        onDataChanged: () => onDataChangedCount += 1,
        settings: settingsWith(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'key',
        ),
      );

      await tester.tap(find.text('Remove from Radarr'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Remove from Radarr'), findsOneWidget);
      expect(onDataChangedCount, 0);
    });

    testWidgets('clear data is a silent no-op when seerr id is missing', (
      tester,
    ) async {
      var onDataChangedCount = 0;

      await _pumpSheet(
        tester,
        onDataChanged: () => onDataChangedCount += 1,
        settings: settingsWith(
          radarrUrl: 'https://radarr.example.com',
          radarrApiKey: 'key',
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Clear data'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Clear data'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Clear data'), findsOneWidget);
      expect(onDataChangedCount, 0);
    });

    testWidgets(
      'an unconfigured Radarr keeps the Media section, dimmed but tappable',
      (tester) async {
        await _pumpSheet(tester, settings: const SettingsModel());

        expect(find.text('Requests'), findsOneWidget);
        // Hiding the section hid the fact with it: the jump stays on screen,
        // drained, and answers with a toast that leads to Radarr's settings.
        expect(find.text('Open in Radarr'), findsOneWidget);
        expect(find.text('Remove from Radarr'), findsOneWidget);
        final dimmed = find.byWidgetPredicate(
          (w) => w is Opacity && w.opacity == GatedAffordance.dimmedOpacity,
        );
        expect(
          find.ancestor(of: find.text('Open in Radarr'), matching: dimmed),
          findsOneWidget,
        );
        // The removal is Seerr's, so a Radarr missing here does not dim it.
        expect(
          find.ancestor(of: find.text('Remove from Radarr'), matching: dimmed),
          findsNothing,
        );

        await tester.tap(find.text('Open in Radarr'));
        await tester.pump();
        expect(find.text('Set up Radarr to open this movie'), findsOneWidget);
        expect(find.text('Set up Radarr'), findsOneWidget);
      },
    );

    testWidgets(
      'an unconfigured Sonarr keeps the Media section and names Sonarr',
      (tester) async {
        await _pumpSheet(
          tester,
          mediaType: 'tv',
          mediaTitle: 'Series',
          tvdbId: 555,
          settings: const SettingsModel(),
        );

        expect(find.text('Open in Sonarr'), findsOneWidget);
        expect(find.text('Remove from Sonarr'), findsOneWidget);

        await tester.tap(find.text('Open in Sonarr'));
        await tester.pump();
        expect(find.text('Set up Sonarr to open this series'), findsOneWidget);
      },
    );

    // P5's shape: Seerr knows its Sonarr, Cupola has none. The removal runs
    // through Seerr, so it asks, names who does it, and goes ahead.
    testWidgets('with no Sonarr in Cupola, Remove from Sonarr still removes '
        'through Seerr', (tester) async {
      final seerr = _RecordingSeerr();
      var changed = 0;
      await _pumpSheet(
        tester,
        mediaType: 'tv',
        mediaTitle: 'Series',
        tvdbId: 555,
        mediaInfo: {'id': 77, 'externalServiceId': 42, 'requests': const []},
        settings: const SettingsModel(),
        seerr: seerr,
        onDataChanged: () => changed++,
      );

      await tester.tap(find.text('Remove from Sonarr'));
      await tester.pumpAndSettle();
      // Asked, never toasted away: no "Set up Sonarr" for a write Sonarr in
      // Cupola has no part in.
      expect(find.text('Set up Sonarr to remove this series'), findsNothing);
      expect(find.text('Remove from Sonarr?'), findsOneWidget);
      expect(
        find.text(
          'Seerr removes this series from its Sonarr server and deletes its '
          'files. This cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, 'Remove and delete files'),
      );
      await tester.pumpAndSettle();
      expect(seerr.filesRemoved, [77]);
      expect(changed, 1);
    });

    testWidgets(
      'Media section is shown when movie has externalServiceId and radarr is configured',
      (tester) async {
        await _pumpSheet(
          tester,
          settings: settingsWith(
            radarrUrl: 'https://radarr.example.com',
            radarrApiKey: 'key',
          ),
        );

        expect(find.text('Open in Radarr'), findsOneWidget);
        expect(find.text('Remove from Radarr'), findsOneWidget);
      },
    );

    testWidgets(
      'Media section is hidden when externalServiceId is null even with radarr configured',
      (tester) async {
        await _pumpSheet(
          tester,
          mediaInfo: {'requests': const []},
          settings: settingsWith(
            radarrUrl: 'https://radarr.example.com',
            radarrApiKey: 'key',
          ),
        );

        expect(find.text('Open in Radarr'), findsNothing);
        expect(find.text('Remove from Radarr'), findsNothing);
      },
    );

    testWidgets('deleting a request asks first, and only a confirm sends it', (
      tester,
    ) async {
      // It fired on the tap, one row above Remove and Clear data, which both
      // asked. The glyph's name said "Delete from library" — the one thing it
      // never touches.
      final seerr = _RecordingSeerr();
      var changed = 0;
      await _pumpSheet(
        tester,
        mediaTitle: 'Nosferatu',
        mediaInfo: {
          'requests': [
            {
              'id': 5,
              'status': 2,
              'createdAt': '2026-09-12T10:00:00Z',
              'type': 'movie',
              'requestedBy': {'id': 2, 'displayName': 'Nadia'},
            },
          ],
        },
        seerr: seerr,
        onDataChanged: () => changed++,
      );

      await tester.tap(find.byTooltip('Delete request'));
      await tester.pumpAndSettle();
      expect(find.text('Delete request?'), findsOneWidget);
      expect(find.text('Nosferatu'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(seerr.deleted, isEmpty);
      expect(changed, 0);

      await tester.tap(find.byTooltip('Delete request'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete request'));
      await tester.pumpAndSettle();
      expect(seerr.deleted, [5]);
      expect(changed, 1);
      expect(find.text('Request deleted'), findsOneWidget);
    });
  });
}

class _RecordingSeerr extends FakeSeerrService {
  final deleted = <int>[];
  final filesRemoved = <int>[];

  @override
  Future<void> deleteRequest(int requestId) async => deleted.add(requestId);

  /// Which copy each removal asked for, in step with [filesRemoved].
  final filesRemoved4k = <bool>[];

  @override
  Future<void> deleteMediaFile(int mediaId, {bool is4k = false}) async {
    filesRemoved.add(mediaId);
    filesRemoved4k.add(is4k);
  }
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  Map<String, dynamic>? mediaInfo,
  String mediaTitle = 'Movie',
  String mediaType = 'movie',
  int tmdbId = 123,
  int? tvdbId,
  VoidCallback? onDataChanged,
  SettingsModel settings = const SettingsModel(),
  SeerrService? seerr,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        if (seerr != null) seerrServiceProvider.overrideWith((ref) => seerr),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: ManageMediaSheet(
              mediaInfo:
                  mediaInfo ?? {'externalServiceId': 42, 'requests': const []},
              mediaTitle: mediaTitle,
              mediaType: mediaType,
              tmdbId: tmdbId,
              tvdbId: tvdbId,
              onDataChanged: onDataChanged ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

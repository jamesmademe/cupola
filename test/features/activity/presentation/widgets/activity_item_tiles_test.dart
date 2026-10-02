import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_search_popup_menu.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../../test_helpers/fake_services.dart';
import '../../../../test_helpers/settings_scope.dart';

void main() {
  group('QueueItemTile', () {
    testWidgets('renders media-first title, release details, and warning', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Movie.2024.2160p.WEB-DL-GROUP',
                'movie': {'title': 'Movie', 'year': 2024},
                'status': 'downloading',
                'trackedDownloadStatus': 'warning',
                'protocol': 'torrent',
                'timeleft': '00:12:00',
                'size': 100,
                'sizeleft': 17,
                'statusMessages': [
                  {
                    'title': 'Import Warning',
                    'messages': ['Needs manual import'],
                  },
                ],
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Movie (2024)'), findsOneWidget);
      expect(
        find.textContaining('Movie.2024.2160p.WEB-DL-GROUP'),
        findsOneWidget,
      );
      // The chip row still flags the warning, and the message the service
      // supplied is now spelled out instead of being fetched and discarded.
      expect(find.text('Warning'), findsOneWidget);
      expect(find.textContaining('Needs manual import'), findsOneWidget);
      expect(find.text('torrent'), findsOneWidget);
      // The label and the percentage come from StatusBadge now, so the
      // percentage is tabular and no longer concatenated into a subtitle string
      // that re-flowed on every tick.
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('83%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('renders fallback title for missing fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(item: {}, serviceType: ServiceType.movies),
          ),
        ),
      );

      expect(find.text('Unknown release'), findsOneWidget);
    });

    testWidgets('does not invent episode zero when episode number is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Frieren.S02.Pack.1080p.WEB-DL-GROUP',
                'series': {'title': 'Frieren: Beyond Journey\'s End'},
                'seasonNumber': 2,
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('Frieren: Beyond Journey\'s End'), findsOneWidget);
      expect(
        find.textContaining('Frieren.S02.Pack.1080p.WEB-DL-GROUP'),
        findsOneWidget,
      );
      expect(find.textContaining('S2 E0'), findsNothing);
    });
  });

  group('HistoryItemTile', () {
    testWidgets('renders media-first title and release name as secondary', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'grabbed',
                'protocol': 'torrent',
                'movie': {'title': 'Movie Title', 'year': 2024},
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Movie Title (2024)'), findsOneWidget);
      expect(find.text('Release.Name'), findsOneWidget);
      expect(find.text('Grabbed'), findsOneWidget);
      expect(find.text('torrent'), findsNothing);
    });

    testWidgets('renders episode code for series history', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'downloadImported',
                'episode': {'seasonNumber': 1, 'episodeNumber': 2},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('S1 E2'), findsWidgets);
      expect(find.text('Imported'), findsOneWidget);
    });

    testWidgets('renders date-only history metadata', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'grabbed',
                'date': '2026-04-03T12:34:56Z',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.textContaining('2026-04-03'), findsOneWidget);
      expect(find.textContaining('12:34'), findsNothing);
    });
  });

  group('BlocklistItemTile', () {
    testWidgets('renders media-first title and reason', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlocklistItemTile(
              item: {
                'sourceTitle': 'Bad.Release',
                'message': 'Rejected',
                'movie': {'title': 'Movie Title', 'year': 2024},
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Movie Title (2024)'), findsOneWidget);
      expect(find.text('Bad.Release'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      // A bare red block glyph became a labelled StatusBadge, so the state is
      // words as well as colour and it reads identically to every other row.
      // The colour is gone now — a release the user rejected is the blocklist
      // obeying, not a fault — so the glyph carries what happened on its own.
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });

    testWidgets('renders fallback title when sourceTitle missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlocklistItemTile(item: {}, serviceType: ServiceType.movies),
          ),
        ),
      );

      expect(find.text('Unknown release'), findsOneWidget);
    });
  });

  group('WantedItemTile', () {
    testWidgets('renders movie title without subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Cool Movie'), findsOneWidget);
    });

    // Dates read `Wed 1 May 2024` (a year only when it is another year), never
    // the sortable `2024-05-01`: the chip and the line above it.
    testWidgets('a movie\'s release date is in the brand book\'s voice', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Cool Movie',
                'inCinemas': '2024-05-01T00:00:00Z',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Release Wed 1 May 2024'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TagChip),
          matching: find.text('Wed 1 May 2024'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2024-05-01'), findsNothing);
    });

    testWidgets('an episode\'s air date chip is in the brand book\'s voice', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Pilot',
                'seasonNumber': 1,
                'episodeNumber': 1,
                'airDateUtc': '2024-05-01T00:00:00Z',
                'series': {'title': 'Breaking Bad'},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(TagChip),
          matching: find.text('Wed 1 May 2024'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2024-05-01'), findsNothing);
    });

    testWidgets('renders search popup when callbacks provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: const {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
              onAutoSearch: () {},
              onInteractiveSearch: () {},
            ),
          ),
        ),
      );

      expect(find.byType(MediaSearchPopupMenu), findsOneWidget);
    });

    testWidgets('hides search popup when callbacks missing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.byType(MediaSearchPopupMenu), findsNothing);
    });

    testWidgets('renders series format with subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Pilot',
                'seasonNumber': 1,
                'episodeNumber': 1,
                'series': {'title': 'Breaking Bad'},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('S1 E1 · Pilot'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('renders music with artist subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Album Name',
                'artist': {'artistName': 'Artist Name'},
              },
              serviceType: ServiceType.music,
            ),
          ),
        ),
      );

      expect(find.text('Album Name'), findsOneWidget);
      expect(find.text('Artist Name'), findsOneWidget);
    });

    testWidgets('cutoff movie shows quality chip and size highlight', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Long Movie Title',
                'status': 'released',
                'qualityProfileId': 7,
                'sizeOnDisk': 8003897815,
                'airDateUtc': '2026-04-03T12:34:56Z',
              },
              serviceType: ServiceType.movies,
              isCutoff: true,
              qualityProfileName: 'HD-1080p',
            ),
          ),
        ),
      );

      expect(find.text('HD-1080p'), findsOneWidget);
      expect(find.text('7.5\u00A0GB'), findsOneWidget);
      expect(find.textContaining('Release 2026-04-03'), findsNothing);
      expect(find.text('Released'), findsNothing);
    });

    testWidgets('handles missing series data gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(item: {}, serviceType: ServiceType.series),
          ),
        ),
      );

      expect(find.text('Unknown episode'), findsOneWidget);
      expect(find.text('Unknown series'), findsOneWidget);
    });
  });

  // The tone rule, on the two chips that broke it: a flagged queue record is a
  // fault (amber), an unmonitored wanted row is backlog (neutral). Both used to
  // be red, which says the service did not answer.
  group('tone rule', () {
    Color chipInk(WidgetTester tester, String label) => tester
        .widget<Text>(
          find.descendant(of: find.byType(TagChip), matching: find.text(label)),
        )
        .style!
        .color!;

    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      final scheme = theme.colorScheme;
      final name = theme.brightness.name;

      testWidgets('a queue warning is amber, not red ($name)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: QueueItemTile(
                item: {
                  'title': 'Movie.2024.WEB-DL',
                  'status': 'downloading',
                  'trackedDownloadStatus': 'warning',
                },
                serviceType: ServiceType.movies,
              ),
            ),
          ),
        );

        // The room's own amber — the day room's is deeper than the dark
        // room's — walked over its wash on the tile.
        expect(
          chipInk(tester, 'Warning'),
          ServiceTheme.onTint(
            statusToneFill(scheme, StatusTone.warning),
            surface: scheme.surfaceContainer,
            tintAlpha: 0.12,
          ),
        );
      });

      testWidgets('an unmonitored wanted row is neutral ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: WantedItemTile(
                item: {
                  'title': 'Cool Movie',
                  'status': 'released',
                  'hasFile': false,
                  'monitored': false,
                },
                serviceType: ServiceType.movies,
              ),
            ),
          ),
        );

        expect(
          chipInk(tester, 'Unmonitored'),
          ServiceTheme.onTint(
            scheme.onSurfaceVariant,
            surface: scheme.surfaceContainer,
            tintAlpha: 0.12,
          ),
        );
        // "Missing from disk" is the list of things to fetch, not damage.
        expect(
          tester
              .widget<Text>(find.text('Movie missing from disk'))
              .style!
              .color,
          scheme.onSurfaceVariant,
        );
      });

      // A release's protocol and a wanted row's date state no status, so their
      // chips wear no tone: the plain chip, like the quality beside them. They
      // used to wear the info blue.
      Future<void> pumpRow(WidgetTester tester, Widget row) =>
          tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(body: row),
            ),
          );

      Iterable<Color?> chipTones(WidgetTester tester) =>
          tester.widgetList<TagChip>(find.byType(TagChip)).map((c) => c.color);

      testWidgets('a queue row\'s protocol is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const QueueItemTile(
            item: {'title': 'Movie.2024.WEB-DL', 'protocol': 'torrent'},
            serviceType: ServiceType.movies,
          ),
        );

        expect(chipTones(tester), [null]);
      });

      testWidgets('a blocklist row\'s protocol is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const BlocklistItemTile(
            item: {'sourceTitle': 'Bad.Release', 'protocol': 'usenet'},
            serviceType: ServiceType.movies,
          ),
        );

        expect(chipTones(tester), [null]);
      });

      // The green scheme role (`tertiary`) is a tone too: a download client and
      // an indexer are names, not a status, and wore it.
      testWidgets('a queue row\'s download client is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const QueueItemTile(
            item: {
              'title': 'Movie.2024.WEB-DL',
              'downloadClient': 'qBittorrent',
            },
            serviceType: ServiceType.movies,
          ),
        );

        expect(find.text('qBittorrent'), findsOneWidget);
        expect(chipTones(tester), [null]);
      });

      testWidgets('a history row\'s indexer is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const HistoryItemTile(
            item: {
              'sourceTitle': 'Release.Name',
              'eventType': 'grabbed',
              'data': {'indexer': 'NZBgeek'},
            },
            serviceType: ServiceType.movies,
          ),
        );

        expect(find.text('NZBgeek'), findsOneWidget);
        expect(chipTones(tester), [null]);
      });

      testWidgets('a blocklist row\'s indexer is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const BlocklistItemTile(
            item: {'sourceTitle': 'Bad.Release', 'indexer': 'NZBgeek'},
            serviceType: ServiceType.movies,
          ),
        );

        expect(find.text('NZBgeek'), findsOneWidget);
        expect(chipTones(tester), [null]);
      });

      testWidgets('a wanted row\'s date is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const WantedItemTile(
            item: {
              'title': 'Pilot',
              'seasonNumber': 1,
              'episodeNumber': 1,
              'airDateUtc': '2024-05-01T00:00:00Z',
              'series': {'title': 'Breaking Bad'},
            },
            serviceType: ServiceType.series,
          ),
        );

        expect(chipTones(tester), [null]);
      });
    }
  });

  group('Queue status normalization', () {
    testWidgets('prefers trackedDownloadState over completed status', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Queued Import',
                'trackedDownloadState': 'importPending',
                'status': 'completed',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Waiting to import'), findsOneWidget);
      expect(find.text('Available'), findsNothing);
    });

    testWidgets('shows no inline progress when not downloading', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Completed Item',
                'status': 'completed',
                'size': 100,
                'sizeleft': 0,
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('GlobalActivityItemTile', () {
    testWidgets('shows warning badge and media-first hierarchy for queue items', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.queue,
                  service: ServiceKey.sonarr,
                  serviceType: ServiceType.series,
                  title: 'Frieren: Beyond Journey\'s End',
                  subtitle:
                      'S1 E3 · Killing Magic · Frieren.S01E03.1080p.WEB-DL-GROUP',
                  status: MediaStatusInfo(
                    availability: MediaAvailability.available,
                    labelOverride: 'Completed',
                    progress: 1,
                    hasWarning: true,
                    detail: 'Import Warning: Unable to Import Automatically',
                  ),
                  raw: {
                    'title': 'Frieren.S01E03.1080p.WEB-DL-GROUP',
                    'series': {'title': 'Frieren: Beyond Journey\'s End'},
                    'episode': {
                      'seasonNumber': 1,
                      'episodeNumber': 3,
                      'title': 'Killing Magic',
                    },
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Frieren: Beyond Journey\'s End'), findsOneWidget);
      expect(
        find.textContaining('Frieren.S01E03.1080p.WEB-DL-GROUP'),
        findsOneWidget,
      );
      // The bare "Warning" chip is gone: it announced that something was wrong
      // while withholding the message the service had already supplied. The
      // resolved status carries the tone, and the detail is now spelled out.
      expect(find.text('Warning'), findsNothing);
      expect(
        find.textContaining('Unable to Import Automatically'),
        findsOneWidget,
      );
    });

    testWidgets('shows search menu for searchable wanted items', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.missing,
                  service: ServiceKey.radarr,
                  serviceType: ServiceType.movies,
                  title: 'Cool Movie',
                  subtitle: 'Radarr',
                  status: resolveWantedStatus(const {}, isCutoff: false),
                  raw: {'id': 42, 'title': 'Cool Movie'},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cool Movie'), findsOneWidget);
      expect(find.byType(MediaSearchPopupMenu), findsOneWidget);
    });

    testWidgets(
      'a failed history row offers Manual import and never Blocklist',
      (tester) async {
        // Decision `act`: blocklisting a HISTORY record is
        // `POST /api/{v}/history/failed/{id}` and no client method calls it,
        // while the queue's Blocklist indexes the queue — sending a history id
        // there would act on a different record. So the failed row's only way
        // out is the import wizard, seeded from `data.droppedPath`: the read
        // that made this row actionable at all.
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: GlobalActivityItemTile(
                  item: GlobalActivityItem(
                    kind: GlobalActivityKind.history,
                    service: ServiceKey.radarr,
                    serviceType: ServiceType.movies,
                    title: 'Dune: Part Two',
                    subtitle: 'Dune.Part.Two.2024.2160p',
                    status: MediaStatusInfo(
                      labelOverride: 'Import failed',
                      toneOverride: StatusTone.warning,
                    ),
                    raw: {
                      'id': 7,
                      'eventType': 'importFailed',
                      'data': {
                        'droppedPath': '/downloads/complete/Dune.2024/dune.mkv',
                      },
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();

        expect(find.text('Manual import'), findsOneWidget);
        expect(find.text('Try another download'), findsNothing);
        expect(find.text('Remove from queue'), findsNothing);
      },
    );

    testWidgets('a history row with nowhere to import offers nothing', (
      tester,
    ) async {
      // The row menu is not decoration: an event that succeeded has nothing to
      // change, and a failed one whose record names no path on disk cannot
      // seed the wizard. Either way the row carries no control rather than a
      // control that does nothing.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.history,
                  service: ServiceKey.radarr,
                  serviceType: ServiceType.movies,
                  title: 'Dune: Part Two',
                  subtitle: 'Dune.Part.Two.2024.2160p',
                  status: MediaStatusInfo(
                    labelOverride: 'Imported',
                    toneOverride: StatusTone.success,
                  ),
                  raw: {'id': 7, 'eventType': 'downloadFolderImported'},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    group('on a desktop window', () {
      Widget host(double width) => ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: const Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.queue,
                  service: ServiceKey.radarr,
                  serviceType: ServiceType.movies,
                  title: 'Dune: Part Two',
                  subtitle: 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
                  figures: '7.5\u00A0GB · 12\u00A0min left',
                  instanceLabel: '4K',
                  status: MediaStatusInfo(
                    pipeline: MediaPipeline.downloading,
                    progress: 0.75,
                  ),
                  raw: {'id': 11},
                ),
              ),
            ),
          ),
        ),
      );

      testWidgets('the table row carries measurements, not the release', (
        tester,
      ) async {
        // Annotation `act`: Size, Done, Speed and Left land as ONE
        // right-aligned tabular cell. That cell used to be handed `subtitle`,
        // which is prose, so the numeric column printed an ellipsised release
        // filename and the measurements appeared nowhere on the row.
        await _onDesktop(() async {
          await tester.pumpWidget(host(1200));
          await tester.pumpAndSettle();

          expect(find.text('7.5\u00A0GB · 12\u00A0min left'), findsOneWidget);
          // The release is not lost — it moved to where prose belongs, under
          // the title.
          expect(
            find.text('Dune.Part.Two.2024.2160p.WEB-DL-GROUP'),
            findsOneWidget,
          );
        });
      });

      testWidgets('a narrower window sheds cells, never the shape', (
        tester,
      ) async {
        // The gate was `isDesktopShell && width >= 1100`, so dragging a window
        // under 1100 swapped the whole list for phone cards — a different
        // information architecture at a size reached by moving a mouse. The
        // size-class rule is the opposite: fewer parts, never smaller ones.
        await _onDesktop(() async {
          await tester.pumpWidget(host(900));
          await tester.pumpAndSettle();

          // Still a row, not the phone's card.
          expect(find.byType(AppCard), findsNothing);
          expect(find.text('Dune: Part Two'), findsOneWidget);

          // And the cells that only pay for themselves with room are gone.
          expect(find.text('7.5\u00A0GB · 12\u00A0min left'), findsNothing);
          // Never the connection: with two Radarr interleaved in one group,
          // a row that drops its name is a row that cannot say which server
          // it is about, to the eye or the ear.
          expect(find.text('4K'), findsOneWidget);
        });
      });
    });

    testWidgets('hides search menu for requests', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => settingsWithServices(const [ServiceKey.seerr]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.request,
                  service: ServiceKey.seerr,
                  serviceType: ServiceType.discover,
                  title: 'Shogun',
                  subtitle: 'sarah · Series',
                  status: MediaStatusInfo(
                    labelOverride: 'Requested',
                    toneOverride: StatusTone.info,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Shogun'), findsOneWidget);
      expect(find.byType(MediaSearchPopupMenu), findsNothing);
    });

    testWidgets('a detail-sheet action actually issues its request', (
      tester,
    ) async {
      // Regression: the sheet's buttons popped the sheet and then ran the
      // action with the *sheet's own* context. `showAppConfirmDialog` still
      // opened (its navigator is captured synchronously), but by the time the
      // user confirmed, the sheet route was disposed — so every
      // `if (!context.mounted) return;` guard in ActivityActions
      // short-circuited and the mutation never ran. No request, no snackbar,
      // no error. The row overflow menu passes the tile's context and worked,
      // which is exactly what hid this.
      final radarr = _RecordingRadarrService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [radarrServiceProvider.overrideWith((ref) => radarr)],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalActivityItemTile(
                item: GlobalActivityItem(
                  kind: GlobalActivityKind.queue,
                  service: ServiceKey.radarr,
                  serviceType: ServiceType.movies,
                  title: 'Furiosa',
                  subtitle: 'Furiosa.2024.2160p.WEB-DL-GROUP',
                  status: MediaStatusInfo(
                    availability: MediaAvailability.unknown,
                    labelOverride: 'Downloading',
                  ),
                  raw: const {
                    'id': 42,
                    'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
                    'movie': {'title': 'Furiosa', 'year': 2024},
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Open the detail sheet, then take the action it offers.
      await tester.tap(find.text('Furiosa'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from queue'), findsOneWidget);

      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();

      // The confirmation still appears — closing the sheet must not take the
      // dialog with it.
      expect(find.text('Remove from queue?'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Remove and delete files'),
      );
      await tester.pumpAndSettle();

      expect(radarr.removed, [42]);
      // And the outcome is reported, rather than the tap vanishing.
      expect(find.text('Removed from queue'), findsOneWidget);
    });
  });
}

/// Records the queue mutations the activity actions issue.
class _RecordingRadarrService extends FakeRadarrService {
  final List<int> removed = [];

  @override
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) async {
    removed.add(id);
  }
}

/// The table draws on a desktop build only, and the override has to be undone
/// inside the test body — `flutter_test` asserts on it before tear-downs run.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

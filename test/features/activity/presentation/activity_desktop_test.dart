/// Activity in a desktop window, P1, whole app: the downloads as a table
/// sorted from its header, a click choosing one for the inspector and a
/// second opening its page, Stop from the row's menu; a compact window opening
/// the page at once; and Needs you a line a fault, its remedy beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/activity/presentation/widgets/download_table.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  String to = ServiceRoutes.activityDownloads,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(
    Profiles.p1,
    now: _now,
    overrides: [
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
      stallClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
    ],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  router.go(to);
  await _answer(tester);
  return (harness, router, container);
}

Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pump();
  await tester.tap(target.first);
  await _answer(tester);
}

/// [matching] in the table of Downloads.
Finder _inTable(Finder matching) =>
    find.descendant(of: find.byType(DownloadTable).first, matching: matching);

/// The titles of the table's rows, top to bottom.
List<String> _order(WidgetTester tester, List<String> titles) {
  final rows = [
    for (final title in titles)
      (title, tester.getTopLeft(_inTable(find.text(title)).first).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (title, _) in rows) title];
}

const _moving = [
  'Cosmos Laundromat · S2 E4',
  'Sprite Fright',
  'Elephants Dream',
  'Cosmos Laundromat · S2 E5',
];

void main() {
  testWidgets(
    'Downloads is a table: Title, Progress, Speed and Left, the figures '
    'in their columns',
    (tester) async {
      final (harness, _, container) = await _app(tester);

      for (final column in ['Title', 'Progress', 'Speed', 'Left']) {
        expect(_inTable(find.text(column)), findsOneWidget, reason: column);
      }
      expect(_inTable(find.text('62%')), findsOneWidget);
      expect(_inTable(find.text('4.2\u00A0MB/s')), findsOneWidget);
      expect(_inTable(find.text('11\u00A0min')), findsOneWidget);
      expect(_inTable(find.text('around 21:04')), findsOneWidget);
      expect(_inTable(find.text('Stuck at 47%')), findsOneWidget);
      // Up next is a table of its own, under no header.
      expect(
        find.descendant(
          of: find.byType(DownloadTable).last,
          matching: find.textContaining('Queued'),
        ),
        findsOneWidget,
      );

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets(
    'a header sorts the table: Progress the furthest first, again the '
    'other way, a third time back to the queue',
    (tester) async {
      final (harness, _, container) = await _app(tester);
      final queue = _order(tester, _moving);

      await _tap(tester, _inTable(find.text('Progress')));
      expect(_order(tester, _moving), [
        'Cosmos Laundromat · S2 E4',
        'Sprite Fright',
        'Elephants Dream',
        'Cosmos Laundromat · S2 E5',
      ]);
      expect(_inTable(find.byIcon(Icons.arrow_downward_rounded)), findsOne);

      await _tap(tester, _inTable(find.text('Progress')));
      expect(_order(tester, _moving), [
        'Cosmos Laundromat · S2 E5',
        'Elephants Dream',
        'Sprite Fright',
        'Cosmos Laundromat · S2 E4',
      ]);
      expect(_inTable(find.byIcon(Icons.arrow_upward_rounded)), findsOne);

      await _tap(tester, _inTable(find.text('Progress')));
      expect(_order(tester, _moving), queue);

      await _tap(tester, _inTable(find.text('Speed')));
      expect(_order(tester, _moving).first, 'Elephants Dream');

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets('a click chooses a download and the inspector shows it; a second '
      'opens its page', (tester) async {
    final (harness, router, container) = await _app(tester);
    expect(find.byType(InspectorPane), findsNothing);

    await _tap(tester, _inTable(find.text('Sprite Fright')));
    expect(find.byType(InspectorPane), findsOneWidget);
    expect(find.text('Selected download'), findsOneWidget);
    final pane = find.byType(InspectorPane);
    expect(
      find.descendant(of: pane, matching: find.byType(DownloadPage)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pane, matching: find.text('Open Sprite Fright')),
      findsOneWidget,
    );
    expect(
      // Radarr writes the hash in capitals, the client in small letters.
      container.read(selectedDownloadProvider)?.key.toLowerCase(),
      WorldDownloads.spriteFright.id.toLowerCase(),
    );
    expect(router.state.uri.path, ServiceRoutes.activityDownloads);

    // Two clicks at once, a double click: its page.
    await tester.tap(_inTable(find.text('Sprite Fright')).first);
    await tester.pump();
    await tester.tap(_inTable(find.text('Sprite Fright')).first);
    await _answer(tester);
    expect(router.state.uri.path, ServiceRoutes.activityDownloadPath);

    await _close(tester, harness, container);
  }, variant: _macOS);

  testWidgets(
    "the inspector's close goes back to the queue, and Escape on the row "
    'lets go too',
    (tester) async {
      final (harness, _, container) = await _app(tester);

      await _tap(tester, _inTable(find.text('Sprite Fright')));
      await _tap(tester, find.byTooltip('Back to the queue'));
      expect(container.read(selectedDownloadProvider), isNull);
      expect(find.text('Selected download'), findsNothing);
      expect(find.byType(InspectorPane), findsOneWidget);

      await _tap(tester, _inTable(find.text('Elephants Dream')));
      expect(find.text('Selected download'), findsOneWidget);
      // The row the keys stand on.
      Focus.of(
        tester.element(_inTable(find.text('Elephants Dream')).first),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _answer(tester);
      expect(container.read(selectedDownloadProvider), isNull);

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets(
    "the row's ⋯ offers Open, Stop and Remove; Stop goes to qBittorrent",
    (tester) async {
      final (harness, router, container) = await _app(tester);

      final more = find.descendant(
        of: find.ancestor(
          of: _inTable(find.text('Sprite Fright')).first,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_Row',
          ),
        ),
        matching: find.byTooltip('More'),
      );
      await _tap(tester, more);
      for (final action in ['Open download', 'Stop', 'Remove']) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
      await _tap(tester, find.text('Stop'));
      final stop = harness.network
          .requestsTo(WorldIds.qbittorrent)
          .where((r) => r.method == 'POST' && r.path.endsWith('/torrents/stop'))
          .toList();
      expect(stop, hasLength(1));
      expect(stop.single.body, contains(WorldDownloads.spriteFright.id));

      await _tap(tester, more);
      await _tap(tester, find.text('Open download'));
      expect(router.state.uri.path, ServiceRoutes.activityDownloadPath);

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets(
    'a compact window has no Speed or Left: they join the line under the '
    'title, and a click opens the page',
    (tester) async {
      final (harness, router, container) = await _app(
        tester,
        size: const Size(1024, 768),
      );

      expect(_inTable(find.text('Speed')), findsNothing);
      expect(
        _inTable(
          find.text(
            'Radarr 1 → qBittorrent · 4.2\u00A0MB/s · 11\u00A0min left · '
            'Anna asked',
          ),
        ),
        findsOneWidget,
      );

      await _tap(tester, _inTable(find.text('Sprite Fright')));
      expect(router.state.uri.path, ServiceRoutes.activityDownloadPath);
      expect(container.read(selectedDownloadProvider), isNull);

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets(
    'on All, Needs you is a line a fault with its remedy beside it, and '
    'one for the requests, with Review',
    (tester) async {
      final (harness, router, container) = await _app(
        tester,
        to: ServiceRoutes.activity,
      );

      expect(find.text('Big Buck Bunny is stuck at 47%'), findsOneWidget);
      expect(find.text('Try another download'), findsOneWidget);
      // The card's sentence is on the Needs you page, not on the line.
      expect(
        find.textContaining('nobody sharing it has the whole file'),
        findsNothing,
      );
      expect(find.text('Review 18'), findsOneWidget);
      expect(find.text('3 requests wait for your approval'), findsOneWidget);

      // The quieter ways out wait behind the ⋯.
      await _tap(
        tester,
        find.bySemanticsLabel('More ways out, Big Buck Bunny is stuck at 47%'),
      );
      expect(find.text('Remove'), findsWidgets);
      expect(find.text('Keep waiting'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _answer(tester);

      await _tap(tester, find.text('Review').last);
      expect(router.state.uri.path, ServiceRoutes.activityRequests);

      await _close(tester, harness, container);
    },
    variant: _macOS,
  );

  testWidgets(
    'a tablet draws Needs you a line a fault too, and its downloads as rows',
    (tester) async {
      final (harness, _, container) = await _app(
        tester,
        size: const Size(1180, 820),
        to: ServiceRoutes.activity,
      );

      expect(find.text('Try another download'), findsOneWidget);
      expect(find.text('3 requests wait for your approval'), findsOneWidget);
      expect(find.byType(DownloadTable), findsNothing);

      await _close(tester, harness, container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

/// One download's own page on P1, whole app: a row opens it, it says where
/// the download stands and how it gets to the server, Stop and Resume go to
/// the client, Remove through the arr; a stuck one leads with its remedy, a
/// link to one that left the queue says so, and a tablet draws it beside the
/// list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/machine_name.dart'
    show machineNameWithBreaks;
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart'
    show DownloadRow;
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester, {
  Size size = const Size(390, 2400),
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

/// [matching] on the download's page.
Finder _onPage(Finder matching) =>
    find.descendant(of: find.byType(DownloadPage), matching: matching);

/// Downloads, then [title]'s row.
Future<void> _open(WidgetTester tester, GoRouter router, String title) async {
  router.go(ServiceRoutes.activityDownloads);
  await _answer(tester);
  await _tap(tester, find.text(title));
}

void main() {
  testWidgets("Sprite Fright's row opens its page: who asked, where it "
      'stands, the steps to Jellyfin, what can be done, the facts', (
    tester,
  ) async {
    final (harness, router, container) = await _app(tester);
    await _open(tester, router, 'Sprite Fright');

    expect(find.byType(DownloadPage), findsOneWidget);
    expect(_onPage(find.text('Sprite Fright')), findsOneWidget);
    expect(
      _onPage(find.text('2021 · out on digital today · Anna asked for it')),
      findsOneWidget,
    );
    expect(_onPage(find.text('62%')), findsOneWidget);
    expect(_onPage(find.text('Downloading')), findsNWidgets(2));
    expect(
      _onPage(
        find.text('4.2\u00A0MB/s · 11\u00A0min left · ready around 21:04'),
      ),
      findsOneWidget,
    );
    for (final step in ['Grabbed', 'Import', 'On Jellyfin']) {
      expect(_onPage(find.text(step)), findsOneWidget, reason: step);
    }
    expect(_onPage(find.text('qBittorrent · 62%')), findsOneWidget);
    expect(_onPage(find.text('around 21:04')), findsOneWidget);

    expect(_onPage(find.text('Open Sprite Fright')), findsOneWidget);
    expect(_onPage(find.text('Stop')), findsOneWidget);
    expect(_onPage(find.text('Remove')), findsOneWidget);

    expect(
      _onPage(find.text(machineNameWithBreaks('Sprite.Fright.2021.1080p.WEB'))),
      findsOneWidget,
    );
    expect(_onPage(find.textContaining('HD-1080p · Radarr')), findsOneWidget);
    expect(_onPage(find.text('Folder')), findsOneWidget);
    expect(_onPage(find.textContaining('qBittorrent · nas')), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('Stop asks qBittorrent to stop it and keep what arrived; '
      'Resume asks it to start again', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _open(tester, router, 'Sprite Fright');

    await _tap(tester, _onPage(find.text('Stop')));
    final stop = harness.network
        .requestsTo(WorldIds.qbittorrent)
        .where((r) => r.method == 'POST' && r.path.endsWith('/torrents/stop'))
        .toList();
    expect(stop, hasLength(1));
    expect(stop.single.body, contains(WorldDownloads.spriteFright.id));
    expect(_onPage(find.text('Stopped')), findsOneWidget);
    expect(_onPage(find.text('Resume')), findsOneWidget);

    await _tap(tester, _onPage(find.text('Resume')));
    expect(
      harness.network
          .requestsTo(WorldIds.qbittorrent)
          .where(
            (r) => r.method == 'POST' && r.path.endsWith('/torrents/start'),
          ),
      hasLength(1),
    );
    expect(_onPage(find.text('Stop')), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('Remove asks first, goes through Radarr\'s queue, and the page '
      'closes', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _open(tester, router, 'Sprite Fright');

    await _tap(tester, _onPage(find.text('Remove')));
    expect(find.text("Remove Sprite Fright's download?"), findsOneWidget);
    await _tap(tester, find.text('Remove download'));

    final removed = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.method == 'DELETE' && r.path.contains('/queue/'))
        .toList();
    expect(removed, hasLength(1));
    expect(removed.single.query['removeFromClient'], 'true');
    expect(removed.single.query['blocklist'], 'false');
    expect(find.byType(DownloadPage), findsNothing);
    expect(router.state.uri.path, ServiceRoutes.activityDownloads);

    await _close(tester, harness, container);
  });

  testWidgets('a stuck download leads with its remedy, and its title\'s '
      'page goes quiet under it', (tester) async {
    final (harness, router, container) = await _app(tester);
    await _open(tester, router, 'Big Buck Bunny');

    expect(_onPage(find.text('Stuck')), findsOneWidget);
    expect(_onPage(find.text('Try another download')), findsOneWidget);
    expect(
      _onPage(find.widgetWithText(OutlinedButton, 'Open Big Buck Bunny')),
      findsOneWidget,
    );
    expect(
      _onPage(find.widgetWithText(FilledButton, 'Open Big Buck Bunny')),
      findsNothing,
    );
    // Remove once, the remedy's.
    expect(_onPage(find.text('Remove')), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('a link to a download that left the queue says so', (
    tester,
  ) async {
    final (harness, router, container) = await _app(tester);
    router.go(
      ServiceRoutes.activityDownload(instanceId: WorldIds.radarr, key: 'gone'),
    );
    await _answer(tester);

    expect(
      find.text('This download is no longer in the queue'),
      findsOneWidget,
    );

    await _close(tester, harness, container);
  });

  testWidgets("a link resolves from its address alone, and the Home's row "
      'opens the page in Activity', (tester) async {
    final (harness, router, container) = await _app(tester);
    router.go(
      ServiceRoutes.activityDownload(
        instanceId: WorldIds.qbittorrent,
        key: WorldDownloads.spriteFright.id,
      ),
    );
    await _answer(tester);
    expect(_onPage(find.text('Open Sprite Fright')), findsOneWidget);

    router.go(ServiceRoutes.home);
    await _answer(tester);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(DownloadRow),
        matching: find.textContaining('Sprite Fright'),
      ),
    );
    expect(router.state.uri.path, ServiceRoutes.activityDownloadPath);
    expect(find.byType(DownloadPage), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('on a tablet the page opens beside the list, whose row wears '
      'the selection; Close closes it', (tester) async {
    final (harness, router, container) = await _app(
      tester,
      size: const Size(1180, 820),
    );
    await _open(tester, router, 'Sprite Fright');

    expect(find.byType(MediaSplitLayout), findsOneWidget);
    expect(find.byType(DownloadPage), findsOneWidget);
    // The list is still there beside it.
    expect(find.byType(ActivityDownloadRow), findsWidgets);
    final selected = tester
        .widgetList<ActivityRowFrame>(find.byType(ActivityRowFrame))
        .where((frame) => frame.selected)
        .map((frame) => frame.label);
    expect(selected, ['Sprite Fright']);

    await _tap(tester, _onPage(find.byIcon(Icons.close_rounded)));
    expect(find.byType(DownloadPage), findsNothing);
    expect(router.state.uri.path, ServiceRoutes.activityDownloads);

    await _close(tester, harness, container);
  });
}

/// Where a row on Activity opens, in the whole app on a household's servers:
/// a title lands on its page under the tab it was opened from, a transfer no
/// arr asked for on its client, and Back returns to the view it left.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _gb = 1024 * 1024 * 1024;

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// The whole app, on [profile]'s household, with its own router.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(
    profile,
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

/// Lets the household's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app down, then its providers: the whole app keeps timers of its own
/// that only the container's end cancels.
Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

Future<void> _tap(WidgetTester tester, Finder row) async {
  await tester.ensureVisible(row.first);
  await tester.pump();
  await tester.tap(row.first);
  await _answer(tester);
}

/// [matching] inside the section named [title].
Finder _inSection(String title, Finder matching) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ActivitySection && widget.title == title,
  ),
  matching: matching,
);

/// The view Activity is drawing.
ActivityTab _view(WidgetTester tester) =>
    tester.widget<ActivityPage>(find.byType(ActivityPage).first).tab;

void main() {
  testWidgets('a download an arr asked for opens its title in that arr, and '
      'Back returns to Downloads', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activityDownloads);
    await _answer(tester);

    await _tap(tester, find.text('Sprite Fright'));

    // The title's one page, under the Library tab of the arr it came from.
    expect(
      router.state.uri.path,
      '${ServiceRoutes.radarrLibrary}/media/movie/'
      '${WorldTitles.spriteFright.tmdbId}',
    );
    // On the connection the row came from, never the lens's.
    expect(router.state.uri.queryParameters['i'], isNotEmpty);

    router.pop();
    await _answer(tester);

    expect(router.state.uri.path, ServiceRoutes.activityDownloads);
    expect(_view(tester), ActivityTab.downloads);

    await _close(tester, harness, container);
  });

  testWidgets('a transfer no arr asked for opens on its client', (
    tester,
  ) async {
    final (harness, router, container) = await _app(
      tester,
      Profiles.p1.withDownloads([
        const WorldDownload(
          id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345790',
          release: 'Hand.Added.2024.1080p',
          client: 'qbittorrent',
          state: DownloadState.downloading,
          progress: 0.4,
          size: _gb,
          speed: 2 * 1024 * 1024,
        ),
      ]),
    );
    router.go(ServiceRoutes.activityDownloads);
    await _answer(tester);

    await _tap(tester, find.text('Hand.Added.2024.1080p'));

    expect(router.state.uri.path, startsWith(ServiceRoutes.qbittorrent));

    await _close(tester, harness, container);
  });

  testWidgets('an import in History opens its title in that arr, and Back '
      'returns to History', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activityHistory);
    await _answer(tester);

    await _tap(tester, find.textContaining('Spring'));

    expect(
      router.state.uri.path,
      startsWith('${ServiceRoutes.radarrLibrary}/media/movie/'),
    );

    router.pop();
    await _answer(tester);

    expect(router.state.uri.path, ServiceRoutes.activityHistory);
    expect(_view(tester), ActivityTab.history);

    await _close(tester, harness, container);
  });

  testWidgets("a request in Everyone's requests opens its title under "
      'Activity, and Back returns to All', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activity);
    await _answer(tester);

    await _tap(
      tester,
      _inSection("Everyone's requests", find.text('Sprite Fright')),
    );

    expect(
      router.state.uri.path,
      '${ServiceRoutes.activity}/media/movie/${WorldTitles.spriteFright.tmdbId}',
    );
    // A way back: the page is pushed onto the view, not put in its place.
    expect(router.canPop(), isTrue);

    router.pop();
    await _answer(tester);

    expect(router.state.uri.path, ServiceRoutes.activity);
    expect(_view(tester), ActivityTab.all);

    await _close(tester, harness, container);
  });

  testWidgets('the link under Everyone\'s requests opens the Requests '
      'view', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activity);
    await _answer(tester);

    await _tap(tester, find.text('All 8 requests'));
    expect(router.state.uri.path, ServiceRoutes.activityRequests);
    expect(_view(tester), ActivityTab.requests);

    await _close(tester, harness, container);
  });
}

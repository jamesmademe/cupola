/// A film opened from the app's own entry points lands on its one page, under
/// the tab it was opened from, and the page draws it: what a route test alone
/// cannot say (a placeholder and a real screen resolve the same).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The whole app, on [profile]'s household, with its own router.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  tester.view.physicalSize = const Size(390, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The household's startup overrides, onboarding done included.
  final harness = await ProfileHarness.start(profile);
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
/// (polls, a search asked again) that only the container's end cancels.
Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

/// The title page the user sees.
Iterable<MediaPage> _shown(WidgetTester tester) =>
    tester.widgetList<MediaPage>(find.byType(MediaPage).hitTestable());

void main() {
  testWidgets('a film in the Radarr library opens on its own page, in the '
      'Library tab', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.radarrLibrary);
    await _answer(tester);

    final tile = find.bySemanticsLabel(RegExp('^Tears of Steel'));
    await tester.ensureVisible(tile.first);
    await tester.tap(tile.first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.radarrLibrary}/media/movie/'
      '${WorldTitles.tearsOfSteel.tmdbId}',
    );
    expect(_shown(tester).map((page) => page.mediaKey), [
      MediaKey.movie(WorldTitles.tearsOfSteel.tmdbId),
    ]);
    expect(find.text('On your server'), findsOneWidget);

    await _close(tester, harness, container);
  });

  testWidgets('a link that names a film by Radarr\'s own id lands on its '
      'page, on that copy', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.radarrMovie(5, instanceId: WorldIds.radarr));
    await _answer(tester);

    expect(
      router.state.uri.toString(),
      startsWith(
        '${ServiceRoutes.radarrLibrary}/media/movie/'
        '${WorldTitles.tearsOfSteel.tmdbId}?',
      ),
    );
    expect(router.state.uri.queryParameters['i'], WorldIds.radarr);
    expect(_shown(tester).single.focus, WorldIds.radarr);
    expect(find.text('Tears of Steel'), findsWidgets);

    await _close(tester, harness, container);
  });
}

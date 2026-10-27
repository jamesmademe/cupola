import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/presentation/unknown_place_screen.dart';
import 'package:cupola/main.dart' show CupolaApp;

import '../test_helpers/demo_artwork.dart';
import '../test_helpers/profiles/profiles.dart';

/// Every place of the demo, on a phone: the four tabs and Settings' pages,
/// every tab of every service, a title, a series, a person, a collection,
/// a download and a library's own pages. On each the app throws nothing,
/// lands where it was sent, and asks the world nothing it cannot answer: a
/// call the world does not cover is a silent 404 in the demo, and this is
/// where it is caught.
void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    SharedPreferences.resetStatic();
  });

  testWidgets('every route of the demo is answered', (tester) async {
    useDemoArtworkFiles();
    final session = (await tester.runAsync(
      () => DemoSession.start(leaving: const SettingsModel()),
    ))!;
    addTearDown(session.end);
    session.network.followFakeTime(tester.binding);
    final thrown = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) =>
        thrown.add(details.exceptionAsString().split('\n').first);
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...session.overrides,
          // The polls' timers would outlive the test; each has its own.
          homeLivePollProvider.overrideWith((ref) {}),
          homeRecoveryPollProvider.overrideWith((ref) {}),
          activityLivePollProvider.overrideWith((ref, tab) {}),
          featuredAdvancesProvider.overrideWithValue(false),
        ],
        child: const CupolaApp(),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final router = ProviderScope.containerOf(
      tester.element(find.byType(CupolaApp)),
    ).read(routerProvider);

    const settings = [
      'region',
      'appearance',
      'certificates',
      'hints',
      'background-search',
      'connections',
      'home',
      'notifications',
    ];
    final routes = [
      ServiceRoutes.home,
      ServiceRoutes.discover,
      ServiceRoutes.activity,
      ServiceRoutes.activityDownloads,
      '/stack',
      ServiceRoutes.settings,
      for (final page in settings) '${ServiceRoutes.settings}/$page',
      for (final MapEntry(key: service, value: tabs) in serviceTabs.entries)
        for (final tab in tabs)
          '${ServiceRoutes.forService(service)}/${tab.segment}',
      ServiceRoutes.forService(ServiceKey.truenas),
      for (final title in [
        WorldTitles.spriteFright,
        WorldTitles.sintel,
        WorldTitles.charge,
      ])
        ServiceRoutes.media(
          MediaKey.movie(title.tmdbId),
          from: ServiceRoutes.discover,
        ),
      ServiceRoutes.media(
        MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
        from: ServiceRoutes.discover,
      ),
      ServiceRoutes.person(90001, from: ServiceRoutes.discover),
      ServiceRoutes.collection(90101, from: ServiceRoutes.discover),
      ServiceRoutes.qbittorrentTorrent(WorldDownloads.spriteFright.id),
      ServiceRoutes.radarrMovie(1),
      ServiceRoutes.sonarrSeries(1),
    ];

    final failures = <String>[];
    var seen = 0;
    for (final route in routes) {
      thrown.clear();
      router.go(route);
      await settle();
      final unanswered = session.network.unanswered.skip(seen).toList();
      seen = session.network.unanswered.length;
      if (thrown.isNotEmpty) failures.add('$route threw: ${thrown.first}');
      for (final request in unanswered) {
        failures.add('$route asked unanswered: $request');
      }
      if (find.byType(UnknownPlaceScreen).evaluate().isNotEmpty) {
        failures.add('$route landed nowhere');
      }
    }
    // Unmounted before the verdict: a failure must not leave the app's
    // timers running into the test's teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(routes.length, greaterThan(100));
    // A healthy sweep takes about half a minute; a route that never settles
    // fails here rather than at the binding's ten minutes.
  }, timeout: const Timeout(Duration(minutes: 3)));
}

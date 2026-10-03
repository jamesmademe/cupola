/// The canonical Media page against the households: who the title is, the
/// one lead, and every row spoken as one sentence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/file_info_section.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title,
) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await pumpWithProfile(
    tester,
    profile,
    child: MediaPage(mediaKey: MediaKey.movie(title.tmdbId)),
    settle: false,
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return harness;
}

/// The page under a router, for the rows that lead somewhere: anything
/// under Settings draws its own location.
Future<(ProfileHarness, GoRouter)> _pumpRouted(
  WidgetTester tester,
  ConfigProfile profile,
  WorldTitle title,
) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            MediaPage(mediaKey: MediaKey.movie(title.tmdbId)),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) => Text('at ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router);
}

/// Lets the profile's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('P1, Tears of Steel: its title, Play on Jellyfin, its rows', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.text('Play on Jellyfin'), findsOneWidget);
    // The marks: Jellyfin's copy is 2160p in HDR10.
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HDR10'), findsOneWidget);
    expect(find.text('On your server'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Available$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Bazarr\. DE wanted$')),
      findsOneWidget,
    );
    expect(find.text('Manage'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('Files & quality opens on each copy\'s file, read only then', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.byType(FileInfoSection), findsNothing);
    await tester.tap(find.text('Files & quality'));
    await tester.pump();

    expect(find.byType(FileInfoSection), findsNWidgets(2));

    await harness.unmount(tester);
  });

  testWidgets('History opens on each copy\'s own imports', (tester) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('History'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 1080p Bluray\. ')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Imported\. 2160p Bluray\. ')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P4, without Seerr: one dimmed row that sets it up', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    expect(find.text('Set up Seerr'), findsOneWidget);
    expect(find.text('Watchlist'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P7, Jellyfin silent: no Play, and its row offers Retry', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    expect(find.textContaining('Play on'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Did not answer.*Retry$')),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('a row not set up is the way to its form, pill and all', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p4,
      WorldTitles.tearsOfSteel,
    );

    await tester.tap(find.text('Set up Seerr'));
    await tester.pumpAndSettle();
    expect(
      find.text('at ${ServiceRoutes.setUp(ServiceKey.seerr)}'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Retry asks the silent connection again, and only it', (
    tester,
  ) async {
    final (harness, _) = await _pumpRouted(
      tester,
      Profiles.p7,
      WorldTitles.tearsOfSteel,
    );
    // By address and port: the household's services share a host.
    String at(ServiceKey service) => Uri.parse(
      harness.profile.settings.instancesOf(service).first.url,
    ).authority;
    int asked(ServiceKey service) => harness.network.requests
        .where((request) => request.uri.authority == at(service))
        .length;
    final jellyfin = asked(ServiceKey.jellyfin);
    final radarr = asked(ServiceKey.radarr);
    final bazarr = asked(ServiceKey.bazarr);
    expect(jellyfin, greaterThan(0));

    // Bazarr is silent too, and keeps its own Retry.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Jellyfin\. .*Retry$')));
    await _answer(tester);

    expect(asked(ServiceKey.jellyfin), greaterThan(jellyfin));
    expect(asked(ServiceKey.radarr), radarr);
    expect(asked(ServiceKey.bazarr), bazarr);

    await harness.unmount(tester);
  });

  testWidgets('Subtitles opens on what Bazarr has and still wants', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Subtitles'));
    await tester.pump();
    expect(find.text('Wanted'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Search releases asks which copy when there are two', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p7, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    expect(
      find.bySemanticsLabel('Search releases on Radarr 1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Search releases on Radarr · 4K'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('Search releases on one copy opens its releases', (tester) async {
    final harness = await _pump(tester, Profiles.p4, WorldTitles.tearsOfSteel);

    await tester.tap(find.text('Search releases'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Releases'), findsWidgets);

    await harness.unmount(tester);
  });
}

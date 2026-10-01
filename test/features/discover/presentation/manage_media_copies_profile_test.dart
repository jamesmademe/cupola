import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Manage acts on the copy, the server and the connection that hold a title.
///
/// P1's Seerr keeps Elephants Dream on Radarr (id 6) and on Radarr 4K (id 1),
/// and Spring on Radarr 4K alone; Cupola connects to both servers. P5's Seerr
/// keeps its titles on a Radarr Cupola has no connection to.
void main() {
  Future<(ProfileHarness, List<String>)> pump(
    WidgetTester tester,
    ConfigProfile profile,
    WorldTitle title,
  ) async {
    final pushed = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: DiscoverDetailScreen(
              mediaId: title.tmdbId,
              mediaType: 'movie',
              heroTag: 'discover_movie_${title.key}',
            ),
          ),
        ),
        GoRoute(
          path: '${ServiceRoutes.radarrMovieBase}/:id',
          builder: (context, state) {
            pushed.add(state.uri.toString());
            return const Scaffold(body: Text('Radarr movie'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    final harness = await ProfileHarness.start(profile);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await harness.settle(tester);

    final manage = find.byIcon(Icons.settings_outlined);
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await harness.settle(tester);
    return (harness, pushed);
  }

  Future<void> tapInSheet(
    WidgetTester tester,
    ProfileHarness harness,
    String label,
  ) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await harness.settle(tester);
  }

  testWidgets('P1: a title in HD and in 4K has a pair for each copy', (
    tester,
  ) async {
    final (harness, _) = await pump(
      tester,
      Profiles.p1,
      WorldTitles.elephantsDream,
    );

    // There was one pair, for the standard copy, whatever the title held.
    expect(find.text('Open in Radarr'), findsOneWidget);
    expect(find.text('Remove from Radarr'), findsOneWidget);
    expect(find.text('Open in Radarr · 4K'), findsOneWidget);
    expect(find.text('Remove from Radarr · 4K'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P1: removing the 4K copy asks Seerr for the 4K copy', (
    tester,
  ) async {
    final (harness, _) = await pump(
      tester,
      Profiles.p1,
      WorldTitles.elephantsDream,
    );

    await tapInSheet(tester, harness, 'Remove from Radarr · 4K');
    expect(find.text('Remove from Radarr · 4K?'), findsOneWidget);
    expect(
      find.text(
        'Seerr removes this movie from Radarr · 4K and deletes its files. '
        'This cannot be undone.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Remove and delete files'),
    );
    await harness.settle(tester);

    final removals = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'DELETE')
        .map((r) => r.uri);
    // It sent no `is4k`, and Seerr removed the standard copy.
    expect(removals.single.path, '/api/v1/media/9761/file');
    expect(removals.single.queryParameters['is4k'], 'true');

    await harness.unmount(tester);
  });

  testWidgets('P1: Open goes to the copy on its own connection', (
    tester,
  ) async {
    final (harness, pushed) = await pump(
      tester,
      Profiles.p1,
      WorldTitles.elephantsDream,
    );

    await tapInSheet(tester, harness, 'Open in Radarr · 4K');

    // Radarr 4K's id for the film, on Radarr 4K: the lens looked the title
    // up on whichever Radarr it was on.
    expect(pushed, [
      ServiceRoutes.radarrMovie(1, instanceId: WorldIds.radarr4k),
    ]);

    await harness.unmount(tester);
  });

  testWidgets('P1: a title only in 4K has its Media section', (tester) async {
    final (harness, _) = await pump(tester, Profiles.p1, WorldTitles.spring);

    expect(find.text('Remove from Radarr · 4K'), findsOneWidget);
    expect(find.text('Remove from Radarr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P5: a Radarr known only to Seerr is said to be, and Open '
      'leads to its setup', (tester) async {
    final (harness, _) = await pump(tester, Profiles.p5, WorldTitles.coffeeRun);

    final dimmed = find.byWidgetPredicate(
      (w) => w is Opacity && w.opacity == GatedAffordance.dimmedOpacity,
    );
    expect(
      find.ancestor(of: find.text('Open in Radarr'), matching: dimmed),
      findsOneWidget,
    );
    await tapInSheet(tester, harness, 'Open in Radarr');
    expect(
      find.text('Radarr is known only to Seerr. Set it up to open this movie.'),
      findsOneWidget,
    );
    expect(find.text('Set up Radarr'), findsOneWidget);

    await harness.unmount(tester);
  });
}

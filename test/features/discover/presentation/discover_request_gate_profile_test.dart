import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Request is gated on what Seerr would take, never on Seerr holding a row.
///
/// P5 is the stack the old gate failed worst: Seerr and Jellyfin, with the
/// Radarr and Sonarr known only through Seerr. Every title Seerr had a row for
/// read "Requested · Radarr is already tracking this.", including a film
/// whose standard copy Seerr has never seen and a series with seasons still
/// to ask for.
void main() {
  final request = find.byWidgetPredicate(
    (widget) => widget is FilledButton && widget.onPressed != null,
  );

  Future<void> expectRequestable(WidgetTester tester, Widget page) async {
    final harness = await pumpWithProfile(tester, Profiles.p5, child: page);

    expect(find.text('Request'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Request'), matching: request),
      findsOneWidget,
    );
    expect(find.text('Requested'), findsNothing);
    expect(find.textContaining('already tracking'), findsNothing);
    // The row is still there to manage.
    expect(find.text('Manage'), findsOneWidget);

    await harness.unmount(tester);
  }

  testWidgets('P5: a film Seerr holds only in 4K can be requested', (
    tester,
  ) async {
    // Spring: standard status 1, 4K status 5. The sheet sends a standard
    // request, which Seerr takes.
    await expectRequestable(
      tester,
      DiscoverDetailScreen(
        mediaId: WorldTitles.spring.tmdbId,
        mediaType: 'movie',
        heroTag: 'discover_movie_spring',
      ),
    );
  });

  testWidgets('P5: a partly available series can request the rest', (
    tester,
  ) async {
    // Night Shift: status 4, partially available.
    await expectRequestable(
      tester,
      DiscoverDetailScreen(
        mediaId: WorldTitles.nightShift.tmdbId,
        mediaType: 'tv',
        heroTag: 'discover_tv_nightShift',
      ),
    );
  });

  testWidgets('P5: a film Seerr has on its way still reads Requested', (
    tester,
  ) async {
    // Sprite Fright: processing, with an approved request.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p5,
      child: DiscoverDetailScreen(
        mediaId: WorldTitles.spriteFright.tmdbId,
        mediaType: 'movie',
        heroTag: 'discover_movie_spriteFright',
      ),
    );

    expect(find.text('Requested'), findsOneWidget);
    expect(find.text('Radarr is already tracking this.'), findsOneWidget);

    await harness.unmount(tester);
  });
}

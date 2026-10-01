import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A Seerr page reads its title's code in its server's own numbering.
///
/// P5 is Seerr and Jellyfin, with the Radarr known only through Seerr: the
/// stack where "Remove from Radarr" is Seerr's to do, and where the code it
/// leaves behind, Seerr's DELETED 7, used to read "Unknown". Seerr numbers
/// AVAILABLE 5, BLOCKLISTED 6, DELETED 7; Overseerr AVAILABLE 5, DELETED 6.
void main() {
  const tmdb = 730154; // Coffee Run, on Radarr as id 3.

  Map<String, Object?> details(int status) => {
    'id': tmdb,
    'title': 'Coffee Run',
    'releaseDate': '2020-05-29',
    'mediaInfo': {
      'id': 5,
      'tmdbId': tmdb,
      'mediaType': 'movie',
      'status': status,
      'status4k': 1,
      'externalServiceId': 3,
      'requests': const <Object?>[],
    },
  };

  MediaStatusInfo badge(WidgetTester tester) => tester
      .widget<StatusBadge>(
        find.descendant(
          of: find.byType(MediaDetailPosterRow),
          matching: find.byType(StatusBadge),
        ),
      )
      .info;

  final request = find.byWidgetPredicate(
    (widget) => widget is FilledButton && widget.onPressed != null,
  );

  Future<ProfileHarness> pump(
    WidgetTester tester, {
    required int Function() status,
    String? version,
    void Function(ProfileNetwork network)? routes,
  }) async {
    final harness = await ProfileHarness.start(Profiles.p5);
    harness.network.on(
      WorldIds.seerr,
      'GET',
      '/api/v1/movie/$tmdb',
      (_) => NetworkReply.json(details(status())),
    );
    if (version != null) {
      harness.network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/status',
        (_) => NetworkReply.json({'version': version}),
      );
    }
    routes?.call(harness.network);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          // The shell's Scaffold, which the removal's toast lands in.
          home: const Scaffold(
            body: DiscoverDetailScreen(
              mediaId: tmdb,
              mediaType: 'movie',
              heroTag: 'discover_movie_coffeeRun',
            ),
          ),
        ),
      ),
    );
    await harness.settle(tester);
    return harness;
  }

  testWidgets('P5: after Remove from Radarr the title reads Deleted, and can '
      'be requested again', (tester) async {
    var status = 5;
    final harness = await pump(
      tester,
      status: () => status,
      routes: (network) =>
          network.on(WorldIds.seerr, 'DELETE', '/api/v1/media/5/file', (_) {
            // What Seerr does to its row when it removes the file.
            status = 7;
            return const NetworkReply(204);
          }),
    );
    expect(badge(tester).label, 'Available');

    // The caption under the disc is not the control: the disc is.
    final manage = find.byIcon(Icons.settings_outlined);
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await harness.settle(tester);
    await tester.tap(find.text('Remove from Radarr'));
    await harness.settle(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Remove and delete files'),
    );
    await harness.settle(tester);
    expect(
      harness.network
          .requestsTo(WorldIds.seerr)
          .where((r) => r.method == 'DELETE')
          .map((r) => r.uri.path),
      ['/api/v1/media/5/file'],
    );

    // It read "Unknown": the page knew 6 as Deleted and nothing past it.
    expect(badge(tester).label, 'Deleted');
    expect(badge(tester).tone, StatusTone.neutral);
    expect(
      find.ancestor(of: find.text('Request'), matching: request),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('P5: a title blocklisted in Seerr says so, and offers no '
      'Request', (tester) async {
    // The world's Seerr reports 2.7.3: Seerr's numbering, where 6 is barred.
    final harness = await pump(tester, status: () => 6);

    expect(badge(tester).label, 'Blocklisted');
    expect(badge(tester).tone, StatusTone.neutral);
    expect(find.text('Request'), findsNothing);
    expect(
      find.text('Blocklisted in Seerr, which takes no request for it.'),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('Blocklisted'), matching: request),
      findsNothing,
    );

    await harness.unmount(tester);
  });

  testWidgets('P5 on Overseerr: a 6 is a deleted title, requestable again', (
    tester,
  ) async {
    final harness = await pump(tester, status: () => 6, version: '1.33.2');

    expect(badge(tester).label, 'Deleted');
    expect(
      find.ancestor(of: find.text('Request'), matching: request),
      findsOneWidget,
    );
    expect(find.textContaining('Blocklisted'), findsNothing);

    await harness.unmount(tester);
  });
}

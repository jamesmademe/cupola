import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A title the requester cannot ask for reads in their words, never the
/// operator's: `Didn't go through` over a request that failed on the stack,
/// `Can't be requested` over a barred title. The sentence under the button
/// already says who can act; the button names the state the same way.
void main() {
  const tmdb = 730154; // Coffee Run.

  Map<String, Object?> details({required int status, List<Object?>? asked}) => {
    'id': tmdb,
    'title': 'Coffee Run',
    'releaseDate': '2020-05-29',
    'mediaInfo': {
      'id': 5,
      'tmdbId': tmdb,
      'mediaType': 'movie',
      'status': status,
      'status4k': 1,
      'requests': asked ?? const <Object?>[],
    },
  };

  Future<ProfileHarness> pump(
    WidgetTester tester,
    ConfigProfile profile,
    Map<String, Object?> body,
  ) async {
    final harness = await ProfileHarness.start(profile);
    harness.network.on(
      WorldIds.seerr,
      'GET',
      '/api/v1/movie/$tmdb',
      (_) => NetworkReply.json(body),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
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

  // Seerr's MediaRequestStatus 4: the stack refused the approved request.
  final failed = [
    {'id': 9, 'status': 4, 'is4k': false},
  ];

  testWidgets('P2: a request that failed reads "Didn\'t go through"', (
    tester,
  ) async {
    final harness = await pump(
      tester,
      Profiles.p2,
      details(status: 3, asked: failed),
    );

    expect(find.text(Lexicon.requestDidNotGoThrough), findsWidgets);
    expect(find.text(Lexicon.lastRequestFailed), findsWidgets);
    expect(find.text('Request failed'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2: a barred title reads "Can\'t be requested"', (tester) async {
    final harness = await pump(tester, Profiles.p2, details(status: 6));

    expect(find.text(Lexicon.cannotBeRequested), findsWidgets);
    expect(find.text(Lexicon.blockedByOwner), findsWidgets);
    // The button: the poster's status badge still reads the state word.
    expect(
      find.ancestor(
        of: find.text('Blocklisted'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
      findsNothing,
    );

    await harness.unmount(tester);
  });

  testWidgets('P5: the operator keeps "Request failed"', (tester) async {
    final harness = await pump(
      tester,
      Profiles.p5,
      details(status: 3, asked: failed),
    );

    expect(find.text('Request failed'), findsWidgets);
    expect(find.text(Lexicon.requestDidNotGoThrough), findsNothing);

    await harness.unmount(tester);
  });
}

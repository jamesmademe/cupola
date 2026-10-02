import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A title the requester cannot ask for reads in their words, never the
/// operator's: `Didn't go through` over a request that failed on the stack,
/// `Can't be requested` over a barred title, and `Blocked` on its badge. The
/// sentence under the button already says who can act; the button and the
/// badge name the state the same way.
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
    // The badge names the state in their words too, never Seerr's list.
    expect(find.text(Lexicon.blocked), findsWidgets);
    expect(find.text('Blocklisted'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2: a title on the server reads "On the server" twice', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p2, details(status: 5));

    // The badge and the button, never the operator's `Available`.
    expect(find.text(Lexicon.onTheServer), findsNWidgets(2));
    expect(find.text(Lexicon.alreadyOnTheServer), findsOneWidget);
    expect(find.text('Available'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P5: the operator keeps "Blocklisted" on the badge', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p5, details(status: 6));

    expect(find.text('Blocklisted'), findsWidgets);
    expect(find.text(Lexicon.blocked), findsNothing);

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

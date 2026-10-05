/// What a title's page says about Seerr's own states, now that it is the
/// one page a title has: a code read in the server's numbering, the
/// requester's words for a title she cannot ask for, an account that may ask
/// for movies only, and the copy one arr holds while another does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

import '../../test_helpers/profiles/profiles.dart';

/// Charge as Seerr answers it with [status], and [asked] as its requests.
/// No server in these households holds Charge, so nothing else leads.
Map<String, Object?> _charge(int status, {List<Object?> asked = const []}) => {
  'id': WorldTitles.charge.tmdbId,
  'title': WorldTitles.charge.title,
  'releaseDate': '2022-10-11',
  'mediaInfo': {
    'id': 5,
    'tmdbId': WorldTitles.charge.tmdbId,
    'mediaType': 'movie',
    'status': status,
    'status4k': 1,
    'requests': asked,
  },
};

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile, {
  MediaKey? key,
  Map<String, Object?>? seerrSays,
  String? version,
}) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(profile);
  if (seerrSays != null) {
    harness.network.on(
      WorldIds.seerr,
      'GET',
      '/api/v1/movie/${WorldTitles.charge.tmdbId}',
      (_) => NetworkReply.json(seerrSays),
    );
  }
  if (version != null) {
    harness.network.on(
      WorldIds.seerr,
      'GET',
      '/api/v1/status',
      (_) => NetworkReply.json({'version': version}),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaPage(
          mediaKey: key ?? MediaKey.movie(WorldTitles.charge.tmdbId),
        ),
      ),
    ),
  );
  await _answer(tester);
  return harness;
}

Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The lead: a filled button with [label], live or not.
Finder _lead(String label, {required bool live}) => find.byWidgetPredicate(
  (widget) =>
      widget is FilledButton &&
      (widget.onPressed != null) == live &&
      find
          .descendant(of: find.byWidget(widget), matching: find.text(label))
          .evaluate()
          .isNotEmpty,
);

void main() {
  group("the operator, by Seerr's numbering (P5)", () {
    testWidgets('a title barred in Seerr says so, and asks for nothing', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p5, seerrSays: _charge(6));

      expect(_lead('Blocklisted', live: false), findsOneWidget);
      expect(
        find.text('Blocklisted in Seerr, which takes no request for it.'),
        findsOneWidget,
      );
      // Seerr's own row reads the same word.
      expect(find.text('Blocklisted'), findsNWidgets(2));

      await harness.unmount(tester);
    });

    testWidgets('a title Seerr deleted can be asked for again', (tester) async {
      final harness = await _pump(tester, Profiles.p5, seerrSays: _charge(7));

      expect(_lead('Request', live: true), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('on Overseerr a 6 is a deleted title, not a barred one', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p5,
        seerrSays: _charge(6),
        version: '1.33.2',
      );

      expect(_lead('Request', live: true), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.textContaining('Blocklisted'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the requester, about a title she cannot ask for (P2)', () {
    testWidgets("a request that failed: it didn't go through", (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p2,
        seerrSays: _charge(
          3,
          asked: const [
            {'id': 9, 'status': 4, 'is4k': false},
          ],
        ),
      );

      expect(
        _lead(Lexicon.requestDidNotGoThrough, live: false),
        findsOneWidget,
      );
      expect(find.text(Lexicon.lastRequestFailed), findsOneWidget);
      expect(find.text('Request failed'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a barred title: it cannot be requested, never Blocklisted', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p2, seerrSays: _charge(6));

      expect(_lead(Lexicon.cannotBeRequested, live: false), findsOneWidget);
      expect(find.text(Lexicon.blockedByOwner), findsOneWidget);
      expect(find.textContaining('Blocklisted'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a title on the server: nothing to ask for, in her words', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p2, seerrSays: _charge(5));

      expect(_lead(Lexicon.onTheServer, live: false), findsOneWidget);
      expect(find.text(Lexicon.alreadyOnTheServer), findsOneWidget);
      expect(find.text('Available'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('an account that asks for movies only: a series says why, and '
        'its Request opens no sheet', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p2.withSeerrPermissions(SeerrPermission.requestMovie.value),
        key: MediaKey.tv(WorldTitles.agent327.tmdbId),
      );
      const reason = "You can't ask for series on this server.";
      expect(find.text(reason), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Request'));
      await _answer(tester);
      expect(find.text('Submit request'), findsNothing);
      expect(find.text(reason), findsWidgets);

      await harness.unmount(tester);
    });
  });

  testWidgets('P6: the 4K copy of a movie on disk in HD is added from its '
      'own row, on that Radarr alone', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p6,
      key: MediaKey.movie(WorldTitles.coffeeRun.tmdbId),
    );

    final add = find.text('Add to Radarr · 4K');
    expect(add, findsOneWidget);
    // The copy it holds offers nothing of the kind.
    expect(find.text('Add to Radarr 1'), findsNothing);

    final other = find.text('Radarr 1').evaluate().length;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await _answer(tester);
    // The sheet is that Radarr's, with no choice of another: nothing new
    // names the other one.
    expect(find.text('Add to Radarr · 4K'), findsWidgets);
    expect(find.text('Quality profile'), findsOneWidget);
    expect(find.text('Radarr 1'), findsNWidgets(other));

    await harness.unmount(tester);
  });
}

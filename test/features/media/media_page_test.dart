/// The canonical Media page against the households: who the title is, the
/// one lead, and every row spoken as one sentence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';

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

void main() {
  testWidgets('P1, Tears of Steel: its title, Play on Jellyfin, its rows', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1, WorldTitles.tearsOfSteel);

    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.text('Play on Jellyfin'), findsOneWidget);
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
}

/// Home's figures, driven through the app's real clients on the profiles'
/// fake network: a count is a count of the sources that answered.
///
/// In flight and Recently added each read several services and degrade a
/// failed one to no rows. The figure above the rows used to count the
/// failure as nothing — `0 downloading` over clients that did not answer, and
/// `3 downloading` with SABnzbd dark reading as the whole queue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);

/// P7 with every queue and every library dark as well: Radarr (both),
/// Sonarr, and the rest as P7 already has them.
final _nothingAnswers = Profiles.p7
    .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
    .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer)
    .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.didNotAnswer);

void main() {
  testWidgets('P1: every source answered, so the totals stand alone', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const HomeScreen(),
      surfaceSize: _tall,
    );

    expect(
      find.text('5 downloading · 40.4\u00A0MB/s across 2 clients'),
      findsOne,
    );
    // Both Radarr: the HD's four imports and the 4K's two, and Sonarr's one.
    expect(find.text('7 imported'), findsOne);
    expect(find.textContaining('Not in the total'), findsNothing);
    expect(find.byType(FaultNote), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P7: a total over the sources that answered names who is '
      'missing from it', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await pumpWithProfile(
      tester,
      Profiles.p7,
      child: const HomeScreen(),
      surfaceSize: _tall,
    );

    // Both Radarr and Sonarr answered; Lidarr and SABnzbd are home-only and
    // the device is away; qBittorrent refused the sign-in. The count is
    // theirs, the 4K's two films included, and the line under it names the
    // rest. Why each is missing is the alert band's sentence, so the note does
    // not say it a second time.
    expect(find.text('5 downloading'), findsOne);
    const inFlightNote = 'Not in the total: Lidarr, SABnzbd, qBittorrent';
    expect(find.text(inFlightNote), findsOne);

    expect(find.text('7 imported'), findsOne);
    expect(find.text('Not in the total: Lidarr'), findsOne);

    // Red is spent on the glyph and only because a source did not answer;
    // the sentence stays in secondary ink.
    final note = find.ancestor(
      of: find.text(inFlightNote),
      matching: find.byType(FaultNote),
    );
    expect(
      find.descendant(
        of: note,
        matching: find.byIcon(Icons.error_outline_rounded),
      ),
      findsOne,
    );

    // The header speaks the figure and what qualifies it as one sentence.
    expect(
      find.bySemanticsLabel(
        'In flight, 5 downloading, '
        'Not in the total: Lidarr, SABnzbd, qBittorrent',
      ),
      findsOne,
    );
    // And the note itself is not a second stop.
    expect(find.bySemanticsLabel(inFlightNote), findsNothing);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P7, nothing answering: no figure reads 0, and the region '
      'says why in one quiet line', (tester) async {
    final handle = tester.ensureSemantics();
    final harness = await pumpWithProfile(
      tester,
      _nothingAnswers,
      child: const HomeScreen(),
      surfaceSize: _tall,
    );

    expect(find.text('0 downloading'), findsNothing);
    expect(find.text('0 imported'), findsNothing);
    expect(find.text('— downloading'), findsOne);
    expect(find.text('— imported'), findsOne);
    // No total, so nothing to qualify.
    for (final region in const [
      ServicesInFlightSection,
      ServicesRecentlyAddedSection,
    ]) {
      expect(
        find.descendant(
          of: find.byType(region),
          matching: find.textContaining('Not in the total'),
        ),
        findsNothing,
      );
    }

    // One line each, in place of the rows: the sources that did not answer,
    // then the refusal in its own words.
    expect(
      find.widgetWithText(
        FaultBand,
        'Radarr 1, Radarr 4K and 3 others did not answer. qBittorrent '
        'answered but refused the sign-in.',
      ),
      findsOne,
    );
    expect(
      find.widgetWithText(
        FaultBand,
        'Radarr 1, Radarr 4K and 2 others did not answer.',
      ),
      findsOne,
    );
    // Not the empty copy, which would send the user looking for media.
    expect(find.text('The queue is empty'), findsNothing);
    expect(find.text('Nothing imported yet'), findsNothing);

    expect(
      find.bySemanticsLabel('In flight, downloading, count unavailable'),
      findsOne,
    );

    handle.dispose();
    await harness.unmount(tester);
  });
}

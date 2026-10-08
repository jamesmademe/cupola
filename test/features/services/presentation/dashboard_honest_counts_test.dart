/// Home's figures, driven through the app's real clients on the profiles'
/// fake network: a count is a count of the sources that answered.
///
/// Downloads and Arrived each read several services and degrade a failed one
/// to no rows. The figure above the rows used to count the failure as nothing:
/// `0 downloading` over clients that did not answer, and `3 downloading` with
/// SABnzbd dark reading as the whole queue. Arrived counts titles over the
/// libraries that answered and names them, and says which did not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);

Finder _inArrived(Finder matching) =>
    find.descendant(of: find.byType(HomeArrivedModule), matching: matching);

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

    expect(find.text('5 moving · 1 stuck · 40.4\u00A0MB/s'), findsOne);
    // Four titles: the HD's Coffee Run and Sintel, the 4K's Spring and Tears
    // of Steel. The HD's older copy of Tears of Steel is outside the week, and
    // Sonarr's episode is of a series that was already there.
    expect(_inArrived(find.text('Last 7 days · 4 new')), findsOne);
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
    // theirs, the 4K's two movies included, and the line under it names the
    // rest. Which of them did not answer is Needs you's sentence, so the note
    // does not say it a second time. The speed is a dash: two clients that are
    // set up did not answer, and the rate of the others would understate it.
    expect(find.text('5 moving · 1 stuck · —'), findsOne);
    const inFlightNote = 'Not in the total: Lidarr, SABnzbd, qBittorrent';
    expect(find.text(inFlightNote), findsOne);

    // Arrived counts titles over the libraries that answered, names them, and
    // says under the heading which one did not.
    const arrivedLine = 'Last 7 days · 4 from Radarr 1, Radarr 4K and Sonarr';
    expect(_inArrived(find.text(arrivedLine)), findsOne);
    expect(_inArrived(find.text('Lidarr did not answer.')), findsOne);

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

    // Arrived's note is red the same way: Lidarr did not answer.
    expect(
      find.descendant(
        of: find.ancestor(
          of: _inArrived(find.text('Lidarr did not answer.')),
          matching: find.byType(FaultNote),
        ),
        matching: find.byIcon(Icons.error_outline_rounded),
      ),
      findsOne,
    );

    // The header speaks the figures and what qualifies them as one sentence,
    // the dash as an unknown speed.
    expect(
      find.bySemanticsLabel(
        'Downloads, 5 moving, 1 stuck, speed unknown, '
        'Not in the total: Lidarr, SABnzbd, qBittorrent',
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        'Arrived, Last 7 days, 4 from Radarr 1, Radarr 4K and Sonarr, '
        'Lidarr did not answer.',
      ),
      findsOne,
    );
    // And the notes themselves are not a second stop.
    expect(find.bySemanticsLabel(inFlightNote), findsNothing);
    expect(find.bySemanticsLabel('Lidarr did not answer.'), findsNothing);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P7, nothing answering: no figure reads 0, and the module '
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
    expect(find.text('Last 7 days · 0 new'), findsNothing);
    // No source answered, so the module states no figure at all, not even
    // the dash: its heading stands over the fault, which says why.
    expect(find.textContaining('downloading'), findsNothing);
    expect(find.textContaining('imported'), findsNothing);
    expect(find.text('Downloads'), findsOne);
    expect(find.text('Arrived'), findsOne);
    // No total, so nothing to qualify.
    for (final region in const [HomeDownloadsModule, HomeArrivedModule]) {
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
      _inArrived(
        find.widgetWithText(
          FaultBand,
          'Radarr 1, Radarr 4K and 2 others did not answer.',
        ),
      ),
      findsOne,
    );
    // Not the empty copy, which would send the user looking for media.
    expect(find.text('Nothing is downloading'), findsNothing);
    expect(find.text('Nothing imported yet'), findsNothing);
    expect(find.textContaining('Last 7 days'), findsNothing);

    // The heading speaks the name and nothing else: no count to be read as
    // unavailable, and none to be read as zero.
    expect(find.bySemanticsLabel('Downloads'), findsOne);
    expect(find.bySemanticsLabel('Arrived'), findsOne);

    handle.dispose();
    await harness.unmount(tester);
  });
}

import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: child),
    theme: AppTheme.darkTheme(),
  );

  group('DownloadQueueTile', () {
    testWidgets('speaks as one row rather than four fragments', (tester) async {
      // The plate that serves every Usenet client had no semantics container at
      // all, so a screen reader walked it as a filename, a bare numeral, and a
      // counting-down line with nothing tying them together — and read "63"
      // where a person would say "63 per cent".
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const DownloadQueueTile(
            title: 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
            subtitle: 'Downloading · movies · 2.1 GB left',
            progress: 0.63,
            percentage: 63,
            accent: Colors.teal,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Dune.Part.Two.2024.2160p.WEB-DL-GROUP, 63 per cent, '
          'Downloading · movies · 2.1 GB left',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('keeps its actions on the screen reader\'s path', (
      tester,
    ) async {
      // The row's label is a container, never an exclusion: the overflow menu
      // is the only control on the plate, and a container that swallowed it
      // would take pause, resume and delete off the screen reader's path
      // entirely — the thing the one-plate-for-four-clients rule exists to get
      // right once.
      final handle = tester.ensureSemantics();
      var received = <DownloadQueueCommand>[];

      await tester.pumpWidget(
        host(
          DownloadQueueTile(
            title: 'Job',
            subtitle: 'Paused',
            progress: 0.2,
            percentage: 20,
            accent: Colors.teal,
            actions: DownloadQueueActionsMenu(
              paused: true,
              onCommand: received.add,
            ),
          ),
        ),
      );

      // The row's node has exactly one child and it is tappable: the label
      // describes the job, the control keeps its own node under it.
      final children = <SemanticsNode>[];
      tester.getSemantics(find.byType(DownloadQueueTile)).visitChildren((node) {
        children.add(node);
        return true;
      });
      expect(children, hasLength(1));
      expect(
        children.single.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byType(DownloadQueueActionsMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(received, [DownloadQueueCommand.resume]);

      handle.dispose();
    });

    // Selection is a *state*, not a word glued onto the label: a screen reader
    // says "selected" in its own voice and stops saying it when the selection
    // clears. qBittorrent's private copy tinted the row and told nobody.
    testWidgets('announces selection as a state', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          DownloadQueueTile(
            title: 'Job',
            subtitle: 'Downloading',
            progress: 0.2,
            percentage: 20,
            accent: Colors.teal,
            selected: true,
            onTap: () {},
          ),
        ),
      );

      final data = tester
          .getSemantics(find.byType(DownloadQueueTile))
          .getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      expect(data.label, isNot(contains('selected')));

      handle.dispose();
    });

    // A plate with no gestures is a plate, not a control that highlights and
    // does nothing — and it must not claim a selection state it cannot change.
    testWidgets('a row with no gestures is not a button', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const DownloadQueueTile(
            title: 'Job',
            subtitle: 'Downloading',
            progress: 0.2,
            percentage: 20,
            accent: Colors.teal,
          ),
        ),
      );

      final data = tester
          .getSemantics(find.byType(DownloadQueueTile))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.longPress), isFalse);
      expect(data.flagsCollection.isButton, isFalse);
      // `Tristate.none`, not `isFalse`: a row with no gestures does not claim a
      // selection state at all, which is different from claiming an unselected
      // one — the second would have a screen reader announce "not selected" on
      // every Usenet job in the list.
      expect(data.flagsCollection.isSelected, Tristate.none);

      handle.dispose();
    });

    // "No progress" and "zero progress" are different facts. A queued job that
    // has not started must not draw a 0% bar, which reads as a transfer that is
    // stuck rather than one that has not begun.
    testWidgets('draws no bar when there is no progress to draw', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const DownloadQueueTile(
            title: 'Job',
            subtitle: 'Queued',
            progress: null,
            percentage: 0,
            accent: Colors.teal,
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpWidget(
        host(
          const DownloadQueueTile(
            title: 'Job',
            subtitle: 'Downloading',
            progress: 0,
            percentage: 0,
            accent: Colors.teal,
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('offers the half of the toggle the job is not already in', (
      tester,
    ) async {
      // A running job is offered Pause and a paused one Resume — never both,
      // and never the one it is already doing. Pause is a download-client
      // capability, which is why this menu has it and no \*arr queue row does.
      await tester.pumpWidget(
        host(
          DownloadQueueTile(
            title: 'Job',
            subtitle: 'Downloading',
            progress: 0.2,
            percentage: 20,
            accent: Colors.teal,
            actions: DownloadQueueActionsMenu(paused: false, onCommand: (_) {}),
          ),
        ),
      );

      await tester.tap(find.byType(DownloadQueueActionsMenu));
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });
  });

  group('a stale row trades its ETA for the age of the sample', () {
    Future<void> pump(WidgetTester tester, {Duration? sampleAge}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadQueueTile(
              title: 'Dune.2021.2160p',
              subtitle: '12 min left · 1.2 GB remaining',
              progress: 0.63,
              percentage: 63,
              accent: AppColors.sabnzbd,
              sampleAge: sampleAge,
            ),
          ),
        ),
      );
    }

    testWidgets('the false figure is replaced by the true one', (tester) async {
      // Left alone, a stalled poll leaves the row claiming "12 min left",
      // counting down nothing, and the user reads a healthy transfer where
      // there is a dead connection.
      await pump(tester, sampleAge: const Duration(minutes: 4));

      expect(find.textContaining('12 min left'), findsNothing);
      expect(find.text('as of 4 min ago'), findsOneWidget);
    });

    testWidgets('the bar keeps its position and loses its colour', (
      tester,
    ) async {
      // It is still what the service last said, so it stays — but the accent
      // is what makes a bar read as moving, and this one is not.
      await pump(tester, sampleAge: const Duration(minutes: 4));

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.63, 0.001));
      expect(bar.valueColor!.value, isNot(AppColors.sabnzbd));
    });

    testWidgets('a current row is untouched', (tester) async {
      await pump(tester);

      expect(find.text('12 min left · 1.2 GB remaining'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.valueColor!.value, AppColors.sabnzbd);
    });

    testWidgets('the age reaches the screen reader too', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, sampleAge: const Duration(minutes: 4));

      expect(find.bySemanticsLabel(RegExp('as of 4 min ago')), findsOneWidget);
      handle.dispose();
    });
  });
}

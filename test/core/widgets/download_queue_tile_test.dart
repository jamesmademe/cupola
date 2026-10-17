import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/status_badge.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: child),
    theme: AppTheme.darkTheme(),
  );

  group('DownloadQueueTile', () {
    testWidgets('speaks as one row rather than four fragments', (tester) async {
      // The plate that serves every Usenet client had no semantics container at
      // all, so a screen reader walked it as a filename, a bare numeral, and a
      // counting-down line with nothing tying them together, and read "63"
      // where a person would say "63 percent".
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const DownloadQueueTile(
            title: 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
            subtitle: 'Downloading\u00A0· movies\u00A0· 2.1\u00A0GB left',
            progress: 0.63,
            percentage: 63,
            accent: Colors.teal,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Dune.Part.Two.2024.2160p.WEB-DL-GROUP, 63 percent, '
          'Downloading\u00A0· movies\u00A0· 2.1\u00A0GB left',
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
      // entirely: the thing the one-plate-for-four-clients rule exists to get
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
              subject: 'Big.Buck.Bunny.2008.1080p',
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
    // does nothing, and it must not claim a selection state it cannot change.
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
      // one: the second would have a screen reader announce "not selected" on
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
      // A running job is offered Stop and a stopped one Resume, never both,
      // and never the one it is already doing. Stop is a download-client
      // capability, which is why this menu has it and no \*arr queue row does.
      await tester.pumpWidget(
        host(
          DownloadQueueTile(
            title: 'Job',
            subtitle: 'Downloading',
            progress: 0.2,
            percentage: 20,
            accent: Colors.teal,
            actions: DownloadQueueActionsMenu(
              paused: false,
              subject: 'Big.Buck.Bunny.2008.1080p',
              onCommand: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DownloadQueueActionsMenu));
      await tester.pumpAndSettle();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });

    // The title is the line's one flexible child. Two Flexibles of the same
    // flex split the free width in half, so a name ellipsised with ~100pt of
    // the line empty and the percentage floated short of the edge.
    testWidgets('the title takes the free width; chip and figure trail', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: DownloadQueueTile(
                title: 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
                subtitle: 'Paused\u00A0· movies',
                statusLabel: 'Paused',
                progress: 0.63,
                percentage: 63,
                accent: Colors.teal,
              ),
            ),
          ),
        ),
      );

      final tile = tester.getRect(find.byType(DownloadQueueTile));
      final title = tester.getRect(
        find.text('Dune.Part.Two.2024.2160p.WEB-DL-GROUP'),
      );
      final chip = tester.getRect(find.text('Paused'));
      final figure = tester.getRect(find.text('63%'));

      // The figure ends on the plate's inset (16) and padding (12), not short
      // of them.
      expect(
        tile.right - figure.right,
        closeTo(AppSpacing.lg + AppSpacing.md, 1),
      );
      // And the title runs right up to the chip's gap.
      expect(chip.left - title.right, lessThan(AppSpacing.sm + 7 + 1));
    });

    testWidgets('a long state label goes under the title instead of '
        'starving it', (tester) async {
      const label = 'Error: tracker returned an unregistered torrent';
      const name = 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP';
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 390,
              child: DownloadQueueTile(
                title: name,
                subtitle: 'Errored\u00A0· movies',
                statusLabel: label,
                statusTone: StatusTone.warning,
                progress: 0.63,
                percentage: 63,
                accent: Colors.teal,
              ),
            ),
          ),
        ),
      );

      final title = tester.getRect(find.text(name));
      final chip = tester.getRect(find.text(label));
      // The title keeps the line; the chip and the figure follow under it.
      expect(chip.top, greaterThanOrEqualTo(title.bottom));
      expect(
        tester.getRect(find.text('63%')).top,
        greaterThanOrEqualTo(title.bottom),
      );
      expect(title.width, greaterThan(10 * 14));
      expect(tester.takeException(), isNull);
    });
  });

  group('a stale row trades its ETA for the age of the sample', () {
    Future<void> pump(WidgetTester tester, {Duration? sampleAge}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadQueueTile(
              title: 'Dune.2021.2160p',
              subtitle: '12\u00A0min left\u00A0· 1.2\u00A0GB remaining',
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

      expect(find.textContaining('12\u00A0min left'), findsNothing);
      expect(find.text('as of 4\u00A0min ago'), findsOneWidget);
    });

    testWidgets('the bar keeps its position and loses its colour', (
      tester,
    ) async {
      // It is still what the service last said, so it stays; but the blue
      // tone is what makes a bar read as moving, and this one is not.
      await pump(tester, sampleAge: const Duration(minutes: 4));

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.63, 0.001));
      expect(bar.valueColor!.value, isNot(AppColors.sabnzbd));
    });

    testWidgets('a current row is untouched', (tester) async {
      await pump(tester);

      expect(
        find.text('12\u00A0min left\u00A0· 1.2\u00A0GB remaining'),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      // A transfer in flight is the blue tone, in progress, never the
      // client's colour.
      final context = tester.element(find.byType(DownloadQueueTile));
      final scheme = Theme.of(context).colorScheme;
      expect(
        bar.valueColor!.value,
        statusToneColor(
          scheme,
          StatusTone.info,
          surface: scheme.surfaceContainerHighest,
        ),
      );
      expect(bar.valueColor!.value, isNot(AppColors.sabnzbd));
    });

    testWidgets('a Usenet row keeps its state before the age', (tester) async {
      // The Usenet pair has no chip: its state heads the second line, and it
      // is still what the server last said. Only the figures that count down
      // give way to the age; the torrent rows keep their chip the same way.
      Future<void> pumpUsenet({Duration? sampleAge}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadQueueTile(
              title: 'Metropolis.1927.1080p',
              subtitleLead: 'Downloading\u00A0· movies',
              subtitle: '12\u00A0min\u00A0· 1.2\u00A0GB left',
              progress: 0.65,
              percentage: 65,
              accent: AppColors.sabnzbd,
              sampleAge: sampleAge,
            ),
          ),
        ),
      );

      await pumpUsenet();
      expect(
        find.text(
          'Downloading\u00A0· movies\u00A0· 12\u00A0min\u00A0· 1.2\u00A0GB left',
        ),
        findsOneWidget,
      );

      await pumpUsenet(sampleAge: const Duration(minutes: 6));
      expect(
        find.text('Downloading\u00A0· movies\u00A0· as of 6\u00A0min ago'),
        findsOneWidget,
      );
    });

    testWidgets('the age reaches the screen reader too', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, sampleAge: const Duration(minutes: 4));

      expect(
        find.bySemanticsLabel(RegExp('as of 4\u00A0min ago')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}

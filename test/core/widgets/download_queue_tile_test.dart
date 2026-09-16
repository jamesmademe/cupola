import 'package:flutter/material.dart';
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
}

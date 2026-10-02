import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_edit_dialogs.dart';

/// The three edit dialogs of a torrent's page (category, tags, speed limit).
///
/// What is held here is what they return, and that each one's field controller
/// is owned by the dialog's own `State`: a `showDialog` future completes as the
/// route pops, well before the exit transition ends, so a controller disposed
/// by whoever awaited it is gone while the field is still on screen, and one
/// nobody disposes is never released.
void main() {
  /// Opens [open] from a button and keeps the answer in [answer].
  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<Object?> Function(BuildContext context) open,
    required void Function(Object? answer) onAnswer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => onAnswer(await open(context)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  TextEditingController fieldController(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  bool isDisposed(TextEditingController controller) {
    try {
      controller.addListener(() {});
      return false;
    } on FlutterError {
      return true;
    }
  }

  group('category', () {
    testWidgets('opens on the current one and hands back what was typed', (
      tester,
    ) async {
      Object? answer = 'unset';
      await pumpHost(
        tester,
        open: (context) =>
            showEditCategoryDialog(context, currentCategory: 'tv'),
        onAnswer: (value) => answer = value,
      );
      expect(find.text('Set category'), findsOneWidget);
      expect(fieldController(tester).text, 'tv');

      await tester.enterText(find.byType(TextField), 'movies');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(answer, 'movies');
    });

    testWidgets('an empty field clears it, and Cancel answers nothing', (
      tester,
    ) async {
      Object? answer = 'unset';
      await pumpHost(
        tester,
        open: (context) =>
            showEditCategoryDialog(context, currentCategory: 'tv'),
        onAnswer: (value) => answer = value,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(answer, '');

      answer = 'unset';
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isNull);
    });
  });

  group('tags', () {
    testWidgets('are trimmed, and the keyboard\'s Done saves', (tester) async {
      Object? answer = 'unset';
      await pumpHost(
        tester,
        open: (context) =>
            showEditTagsDialog(context, currentTags: const ['4k', 'dubbed']),
        onAnswer: (value) => answer = value,
      );
      expect(fieldController(tester).text, '4k, dubbed');

      await tester.enterText(find.byType(TextField), ' italian , 4k,, ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(answer, ['italian', '4k']);
    });
  });

  group('speed limit', () {
    Future<Object?> answerFor(WidgetTester tester, String typed) async {
      Object? answer = 'unset';
      await pumpHost(
        tester,
        open: (context) => showSpeedLimitDialog(
          context,
          title: 'Download limit',
          currentLimitBytes: 2048,
        ),
        onAnswer: (value) => answer = value,
      );
      expect(fieldController(tester).text, '2');
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('a figure is KB/s, a comma is a decimal point', (tester) async {
      final answer = await answerFor(tester, '1,5') as SpeedLimitResult;
      expect(answer.bytesPerSecond, 1536);
    });

    testWidgets('empty and zero both clear the limit', (tester) async {
      final empty = await answerFor(tester, '') as SpeedLimitResult;
      expect(empty.bytesPerSecond, 0);
      final zero = await answerFor(tester, '0') as SpeedLimitResult;
      expect(zero.bytesPerSecond, 0);
    });

    testWidgets('something that is not a figure changes nothing', (
      tester,
    ) async {
      final answer = await answerFor(tester, 'fast') as SpeedLimitResult;
      expect(answer.bytesPerSecond, isNull);
    });
  });

  group('the controller', () {
    final dialogs =
        <(String, Future<Object?> Function(BuildContext context), String)>[
          (
            'category',
            (context) => showEditCategoryDialog(context, currentCategory: 'tv'),
            'Save',
          ),
          (
            'tags',
            (context) => showEditTagsDialog(context, currentTags: const ['a']),
            'Save',
          ),
          (
            'speed limit',
            (context) => showSpeedLimitDialog(
              context,
              title: 'Upload limit',
              currentLimitBytes: 0,
            ),
            'Save',
          ),
          (
            'category (cancelled)',
            (context) => showEditCategoryDialog(context, currentCategory: ''),
            'Cancel',
          ),
        ];

    for (final (name, open, tapped) in dialogs) {
      testWidgets('of the $name dialog outlives the pop and is then released', (
        tester,
      ) async {
        await pumpHost(tester, open: open, onAnswer: (_) {});
        final controller = fieldController(tester);

        await tester.tap(find.text(tapped));
        // The route has popped and is fading out: the field is still drawn.
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(TextField), findsOneWidget);
        expect(isDisposed(controller), isFalse);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(isDisposed(controller), isTrue);
      });
    }
  });
}

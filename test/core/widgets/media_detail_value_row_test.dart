import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_detail_value_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _options = <MediaDetailValueOption<int>>[
  MediaDetailValueOption(value: 1, label: 'HD-1080p'),
  MediaDetailValueOption(value: 2, label: 'Ultra-HD'),
];

Future<void> _pump(
  WidgetTester tester, {
  int? value = 1,
  List<MediaDetailValueOption<int>> options = _options,
  Future<void> Function(int)? onChanged,
  String? hint,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaDetailValueRow<int>(
          label: 'Quality profile',
          value: value,
          options: options,
          onChanged: onChanged,
          accent: ServiceKey.sonarr.accent,
          hint: hint,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('MediaDetailValueRow', () {
    testWidgets('a field with no write behind it is not a control', (
      tester,
    ) async {
      // The rule, not the rendering: a picker with nothing behind it is worse
      // than an honest readout, because it fails in the user's hand.
      await _pump(tester);

      expect(find.byType(PressableScale), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      // And not a disabled button either — there is no control here to disable.
      expect(find.byType(MenuAnchor), findsNothing);
    });

    testWidgets('an empty option list disables the row as surely as a null '
        'write does', (tester) async {
      await _pump(tester, options: const [], onChanged: (_) async {});

      expect(find.byType(PressableScale), findsNothing);
    });

    testWidgets('a value the source did not answer reads as a dash', (
      tester,
    ) async {
      await _pump(tester, value: null, onChanged: (_) async {});

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('the row is one node, named and valued, with its hint on the '
        'button itself', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        onChanged: (_) async {},
        hint: 'Changes it on Sonarr',
      );

      // One node, not three fragments: a label, a value and a chevron walked
      // separately is a row a screen reader cannot make a sentence out of. And
      // the hint rides on the button, because a `Semantics(hint:)` wrapped
      // *around* a button is dropped — a button is a semantic boundary.
      expect(
        find.semantics.byLabel('Quality profile'),
        containsSemantics(
          value: 'HD-1080p',
          hint: 'Changes it on Sonarr',
          isButton: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the target clears 44pt', (tester) async {
      await _pump(tester, onChanged: (_) async {});

      // Measured, not declared: `VisualDensity.compact` silently defeats a
      // `minimumSize`, so a control that says 44 can still measure 40.
      expect(
        tester.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(MediaDetailValueRow.minRowHeight),
      );
    });

    testWidgets('a phone edits the field in one sheet and writes the pick', (
      tester,
    ) async {
      final written = <int>[];
      await _pump(tester, onChanged: (id) async => written.add(id));

      await tester.tap(find.byType(PressableScale));
      await tester.pumpAndSettle();

      // One field per sheet. A sheet carrying four selects is an Edit form with
      // a drag handle, which is the thing decision 25 removes.
      expect(find.text('Quality profile'), findsWidgets);
      expect(find.text('Currently HD-1080p'), findsOneWidget);

      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();
      expect(written, [2]);
    });

    testWidgets('re-picking the value it already holds writes nothing', (
      tester,
    ) async {
      var writes = 0;
      await _pump(tester, onChanged: (_) async => writes++);

      await tester.tap(find.byType(PressableScale));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HD-1080p').last);
      await tester.pumpAndSettle();

      // A no-op write to a quality profile can still queue a library-wide
      // upgrade sweep.
      expect(writes, 0);
    });
  });
}

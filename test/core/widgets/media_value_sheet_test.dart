import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_value_sheet.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _profiles = <Map<String, dynamic>>[
  {'id': 1, 'name': 'HD-1080p'},
  {'id': 2, 'name': 'Ultra-HD'},
];

void main() {
  group('qualityProfileOptions', () {
    test("keeps the server's own names and ids, in order", () {
      final options = qualityProfileOptions(_profiles);

      expect(options.map((option) => option.value), [1, 2]);
      expect(options.map((option) => option.label), ['HD-1080p', 'Ultra-HD']);
    });

    test('drops an entry missing its id or its name', () {
      final options = qualityProfileOptions(const [
        {'id': 1, 'name': 'HD-1080p'},
        {'name': 'No id'},
        {'id': 3},
        {'id': '4', 'name': 'Id as text'},
        {'id': 5, 'name': 5},
      ]);

      expect(options.map((option) => option.value), [1]);
    });
  });

  group('the quality profile sheet (showMediaValueSheet)', () {
    testWidgets('every row is a PressableScale target of at least 44pt', (
      tester,
    ) async {
      await _pumpPicker(tester);

      expect(find.byType(PressableScale), findsNWidgets(_profiles.length));
      expect(find.byType(ListTile), findsNothing);
      for (final name in const ['HD-1080p', 'Ultra-HD']) {
        final row = find
            .ancestor(
              of: find.text(name),
              matching: find.byType(PressableScale),
            )
            .first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('names the field and the value it holds now', (tester) async {
      await _pumpPicker(tester);

      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('Currently HD-1080p'), findsOneWidget);
    });

    testWidgets('the selected row is announced, not only coloured', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPicker(tester);

      expect(
        find.semantics.byLabel('HD-1080p').first,
        isSemantics(value: 'Selected'),
      );
      handle.dispose();
    });

    testWidgets('the selected row takes the page accent, not primary', (
      tester,
    ) async {
      await _pumpPicker(tester, accent: ServiceKey.sonarr.accent);

      final check = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_rounded),
      );
      final context = tester.element(find.text('HD-1080p'));
      expect(check.color, isNot(Theme.of(context).colorScheme.primary));
    });

    testWidgets('picking a row answers with that option', (tester) async {
      final answers = <MediaDetailValueOption<int>?>[];
      await _pumpPicker(tester, onAnswer: answers.add);

      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();

      expect(answers.single?.value, 2);
      expect(answers.single?.label, 'Ultra-HD');
    });

    testWidgets('dismissing the sheet answers with nothing', (tester) async {
      final answers = <MediaDetailValueOption<int>?>[];
      await _pumpPicker(tester, onAnswer: answers.add);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(answers, [null]);
    });

    testWidgets('no options, no sheet', (tester) async {
      final answers = <MediaDetailValueOption<int>?>[];
      await _pumpPicker(tester, profiles: const [], onAnswer: answers.add);

      expect(find.byType(PressableScale), findsNothing);
      expect(answers, [null]);
    });
  });
  group('mediaValueMatches', () {
    test('ignores case, and finds words anywhere in the label', () {
      expect(mediaValueMatches('E4 · The Second Cycle', 'second'), isTrue);
      expect(mediaValueMatches('E4 · The Second Cycle', 'SECOND C'), isTrue);
      expect(mediaValueMatches('E4 · The Second Cycle', 'third'), isFalse);
      expect(mediaValueMatches('anything', '  '), isTrue);
    });

    test('a number is a whole number', () {
      expect(mediaValueMatches('E4 · Pilot', '4'), isTrue);
      expect(mediaValueMatches('E14 · Pilot', '4'), isFalse);
      expect(mediaValueMatches('E40 · Pilot', '4'), isFalse);
      expect(mediaValueMatches('E14 · Pilot', '14'), isTrue);
      expect(mediaValueMatches('E14 · Pilot', 'e1'), isFalse);
      expect(mediaValueMatches('4. Intro', '4'), isTrue);
    });
  });

  group('a long list (showMediaValueSheet)', () {
    testWidgets('opens on a search that narrows the rows, and picks from '
        'what is left', (tester) async {
      MediaDetailValueOption<int>? answer;
      await _pumpPicker(
        tester,
        profiles: [
          for (var n = 1; n <= 24; n++) {'id': n, 'name': 'E$n · Episode $n'},
        ],
        onAnswer: (picked) => answer = picked,
      );

      expect(find.byType(SearchBar), findsOneWidget);
      await tester.enterText(find.byType(TextField), '17');
      await tester.pumpAndSettle();
      expect(find.byType(PressableScale), findsOneWidget);
      await tester.tap(find.text('E17 · Episode 17'));
      await tester.pumpAndSettle();
      expect(answer?.value, 17);
    });

    testWidgets('says when nothing matches', (tester) async {
      await _pumpPicker(
        tester,
        profiles: [
          for (var n = 1; n <= 13; n++) {'id': n, 'name': 'E$n'},
        ],
      );
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches "zebra"'), findsOneWidget);
    });

    testWidgets('a short list has no search', (tester) async {
      await _pumpPicker(tester);
      expect(find.byType(SearchBar), findsNothing);
    });
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  Color? accent,
  List<Map<String, dynamic>> profiles = _profiles,
  void Function(MediaDetailValueOption<int>? picked)? onAnswer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final picked = await showMediaValueSheet<int>(
                context,
                title: 'Quality profile',
                value: 1,
                currentLabel: 'HD-1080p',
                options: qualityProfileOptions(profiles),
                accent: accent,
              );
              onAnswer?.call(picked);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

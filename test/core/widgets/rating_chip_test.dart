import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/rating_chip.dart';

Future<void> _pump(WidgetTester tester, RatingChip chip) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: chip)));

void main() {
  group('RatingChip', () {
    testWidgets('prints the score with the scale it is measured on', (
      tester,
    ) async {
      await _pump(
        tester,
        const RatingChip(
          value: '53',
          denominator: '/100',
          votes: 0,
          sourceName: 'Metacritic',
          sourceIcon: 'Metacritic',
        ),
      );

      // A bare `53` next to an 8.4 reads as one comparable set of numbers.
      expect(find.text('53/100'), findsOneWidget);
      expect(find.text('Metacritic'), findsOneWidget);
    });

    testWidgets('speaks the scale as words rather than a slash', (
      tester,
    ) async {
      await _pump(
        tester,
        const RatingChip(
          value: '53',
          denominator: '/100',
          votes: 0,
          sourceName: 'Metacritic',
          sourceIcon: 'Metacritic',
        ),
      );

      // "53 slash 100" is worse than the ambiguity the denominator fixes.
      expect(
        tester.getSemantics(find.byType(RatingChip)),
        containsSemantics(label: 'Metacritic rating 53 out of 100'),
      );
    });

    testWidgets('a percentage source speaks "percent"', (tester) async {
      await _pump(
        tester,
        const RatingChip(
          value: '57',
          denominator: '%',
          votes: 1200,
          sourceName: 'Rotten Tomatoes',
          sourceIcon: 'Rotten Tomatoes',
        ),
      );

      expect(
        tester.getSemantics(find.byType(RatingChip)),
        containsSemantics(
          label: 'Rotten Tomatoes rating 57 percent',
          value: '1200 votes',
        ),
      );
    });
  });
}

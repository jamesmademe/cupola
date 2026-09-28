import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_info_card.dart';

void main() {
  group('MediaInfoCard', () {
    testWidgets('renders nothing when groups is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaInfoCard(groups: [])),
        ),
      );

      expect(find.text('Genre'), findsNothing);
      expect(find.text('Studio'), findsNothing);
    });

    testWidgets('renders group titles and content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaInfoCard(
              groups: const [
                MediaInfoGroup(title: 'Genre', child: Text('Action')),
                MediaInfoGroup(title: 'Studio', child: Text('Warner')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Genre'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
      expect(find.text('Warner'), findsOneWidget);
    });

    // The grid folded at a bare 320 of its own width, and the desktop side
    // track leaves it 316 (380 − 32 gutter − 32 card padding), so Radarr's
    // Details drew one column exactly where the boards draw two.
    Future<Offset> studioOffset(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const MediaInfoCard(
                  groups: [
                    MediaInfoGroup(title: 'Monitored', child: Text('Yes')),
                    MediaInfoGroup(title: 'Studio', child: Text('Prana')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final monitored = tester.getTopLeft(find.text('Monitored'));
      return tester.getTopLeft(find.text('Studio')) - monitored;
    }

    testWidgets('the side track\'s 316pt draws two columns', (tester) async {
      final delta = await studioOffset(tester, 316);
      expect(delta.dy, 0);
      expect(delta.dx, greaterThan(0));
    });

    testWidgets('a 360pt phone\'s 296pt still folds to one column', (
      tester,
    ) async {
      final delta = await studioOffset(tester, 296);
      expect(delta.dx, 0);
      expect(delta.dy, greaterThan(0));
    });
  });

  group('MediaFactsList', () {
    testWidgets('renders nothing when facts is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MediaFactsList(facts: [])),
        ),
      );

      expect(find.text('In cinemas'), findsNothing);
      expect(find.text('2023-06-15'), findsNothing);
    });

    testWidgets('renders label-value pairs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaFactsList(
              facts: const [
                MediaFact('In cinemas', '2023-06-15'),
                MediaFact('Digital', '2023-09-01'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('In cinemas'), findsOneWidget);
      expect(find.text('2023-06-15'), findsOneWidget);
      expect(find.text('Digital'), findsOneWidget);
      expect(find.text('2023-09-01'), findsOneWidget);
    });
  });
}

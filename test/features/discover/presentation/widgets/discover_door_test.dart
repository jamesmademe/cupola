import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_door.dart';

/// A lobby door's corner: the names stack up from the foot and stop under
/// the words, as many as fit.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    double height = 104,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // A third of a phone, as the atrium lays the doors.
              child: SizedBox(
                width: 118,
                height: height,
                child: DiscoverDoor.lobby(
                  title: 'Networks',
                  subtitle: 'Series',
                  names: const ['Prime Video', 'AMC', 'CBS'],
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void expectUnderTheWords(WidgetTester tester) {
    final foot = tester.getBottomLeft(find.text('Series')).dy;
    for (final name in ['Prime Video', 'AMC', 'CBS']) {
      final drawn = find.text(name);
      if (drawn.evaluate().isEmpty) continue;
      expect(
        tester.getTopLeft(drawn).dy,
        greaterThanOrEqualTo(foot),
        reason: '$name sits on the line under the name',
      );
    }
  }

  testWidgets('a door at its floor draws the names that fit under the words, '
      'and drops the rest', (tester) async {
    await pump(tester);

    expect(find.text('Prime Video'), findsOneWidget);
    expect(find.text('AMC'), findsOneWidget);
    expect(find.text('CBS'), findsNothing);
    expectUnderTheWords(tester);
  });

  testWidgets('a taller door draws all three', (tester) async {
    await pump(tester, height: 140);

    for (final name in ['Prime Video', 'AMC', 'CBS']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expectUnderTheWords(tester);
  });

  testWidgets('a larger reading size keeps the names off the words', (
    tester,
  ) async {
    await pump(tester, textScale: DiscoverDoor.largeTextScale);

    expect(find.text('Prime Video'), findsOneWidget);
    expectUnderTheWords(tester);
  });

  group('the People door', () {
    Future<void> pumpFaces(WidgetTester tester, {double textScale = 1}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 118,
                  child: DiscoverDoor.lobby(
                    title: 'People',
                    subtitle: 'Directors, cast',
                    faceUrls: const [
                      'https://image.tmdb.org/t/p/w185/a.jpg',
                      'https://image.tmdb.org/t/p/w185/b.jpg',
                      'https://image.tmdb.org/t/p/w185/c.jpg',
                      'https://image.tmdb.org/t/p/w185/d.jpg',
                    ],
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('three faces at most, under the words, silenced', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpFaces(tester);

      final faces = find.byType(CachedNetworkImage);
      expect(faces, findsNWidgets(3));
      final foot = tester.getBottomLeft(find.text('Directors, cast')).dy;
      for (final face in faces.evaluate()) {
        expect(
          tester.getTopLeft(find.byWidget(face.widget)).dy,
          greaterThan(foot),
        );
      }
      expect(find.bySemanticsLabel('People, Directors, cast'), findsOne);
      semantics.dispose();
    });

    testWidgets('a larger reading size drops the faces off the name', (
      tester,
    ) async {
      await pumpFaces(tester, textScale: 1.6);

      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';

void main() {
  Future<Color> magnifierColour(
    WidgetTester tester, {
    required Color accent,
    required Brightness brightness,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme(),
        home: Scaffold(
          body: SearchBarHeader(onQueryChanged: (_) {}, accent: accent),
        ),
      ),
    );
    return tester.widget<Icon>(find.byIcon(Icons.search_rounded)).color!;
  }

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  testWidgets('a raw accent never reaches the glyph on paper', (tester) async {
    // The defect: the magnifier painted `widget.accent` straight through, and
    // six callers hand it a raw service accent. The field it sits in is
    // `surfaceContainer` — white on the light theme — where Lidarr's pink
    // measures under 2:1 and seven of the seventeen accents are under 3:1.
    final painted = await magnifierColour(
      tester,
      accent: AppColors.lidarr,
      brightness: Brightness.light,
    );

    expect(painted, isNot(AppColors.lidarr));
    expect(
      contrast(painted, AppTheme.lightTheme().colorScheme.surfaceContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('an accent that already reads is left alone', (tester) async {
    // The walk must not "correct" a colour that passes, or every search field
    // in the dark theme shifts hue for no reason.
    final painted = await magnifierColour(
      tester,
      accent: AppColors.lidarr,
      brightness: Brightness.dark,
    );
    expect(painted, AppColors.lidarr);
  });

  testWidgets('the identity survives: the glyph keeps the accent\'s hue', (
    tester,
  ) async {
    // A per-service accent is part of the identity, so the answer is a darker
    // pink, not a neutral gray.
    final painted = await magnifierColour(
      tester,
      accent: AppColors.lidarr,
      brightness: Brightness.light,
    );
    expect(
      HSLColor.fromColor(painted).hue,
      closeTo(HSLColor.fromColor(AppColors.lidarr).hue, 1.0),
    );
  });

  testWidgets('the clear action has an explicit accessible name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SearchBarHeader(
            initialQuery: 'Fight Club',
            onQueryChanged: (_) {},
          ),
        ),
      ),
    );

    final clear = find.bySemanticsLabel('Clear search');
    expect(clear, findsOneWidget);
    final semantics = tester.getSemantics(clear);
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });
}

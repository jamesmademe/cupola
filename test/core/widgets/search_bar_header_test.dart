import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';

void main() {
  Future<Color> magnifierColour(
    WidgetTester tester, {
    required Brightness brightness,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme(),
        home: Scaffold(body: SearchBarHeader(onQueryChanged: (_) {})),
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

  for (final brightness in Brightness.values) {
    testWidgets('the magnifier is the secondary ink ($brightness)', (
      tester,
    ) async {
      // The brand book: the field is the same field whichever service it searches, so the
      // glyph is monochrome; it used to take the caller's service accent,
      // which put seven hues under 3:1 on paper. The secondary ink is spaced
      // for the field's own fill in both rooms.
      final theme = brightness == Brightness.light
          ? AppTheme.lightTheme()
          : AppTheme.darkTheme();
      final painted = await magnifierColour(tester, brightness: brightness);
      expect(painted, theme.colorScheme.onSurfaceVariant);
      expect(
        contrast(painted, theme.colorScheme.surfaceContainer),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

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

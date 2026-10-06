import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/status_badge.dart';

void main() {
  group('HeaderActionRow.buttonHeight', () {
    test('clears the platform touch-target minimums', () {
      // 44pt is iOS' floor and the number this codebase writes down for itself
      // on the detail back button; 48dp is Android's. One shared constant has to
      // clear the larger of the two. It used to be 42.
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(44));
      expect(HeaderActionRow.buttonHeight, greaterThanOrEqualTo(48));
    });
  });

  group('ActionStateGlyph', () {
    testWidgets('morphs idle to busy to a held confirmation', (tester) async {
      await _pumpGlyph(tester);
      expect(find.byIcon(Icons.saved_search_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _pumpGlyph(tester, isBusy: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpGlyph(tester, isConfirmed: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.saved_search_rounded), findsNothing);
    });

    testWidgets('the confirmation says so out loud', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGlyph(tester, isConfirmed: true);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.semantics.byLabel('Auto search complete'), findsOne);
      handle.dispose();
    });

    // The check is the success tone, resolved for the room and for the fill it
    // lands on: through `statusToneColor`, not by reaching for a scheme role.
    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      testWidgets('the confirmation is the walked success tone '
          '(${theme.brightness.name})', (tester) async {
        const fill = Color(0xFFF5A623);
        await _pumpGlyph(tester, isConfirmed: true, theme: theme, fill: fill);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
          statusToneColor(theme.colorScheme, StatusTone.success, surface: fill),
        );
      });
    }

    testWidgets('reduce motion removes the animator, not its duration', (
      tester,
    ) async {
      await _pumpGlyph(tester, isConfirmed: true, reduceMotion: true);

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}

Future<void> _pumpGlyph(
  WidgetTester tester, {
  bool isBusy = false,
  bool isConfirmed = false,
  bool reduceMotion = false,
  ThemeData? theme,
  Color? fill,
}) {
  return _pump(
    tester,
    reduceMotion: reduceMotion,
    theme: theme,
    child: ActionStateGlyph(
      icon: Icons.saved_search_rounded,
      label: 'Auto search',
      isBusy: isBusy,
      isConfirmed: isConfirmed,
      fill: fill,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  double textScale = 1.0,
  bool reduceMotion = false,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: inner!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

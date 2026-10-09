import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';

/// The hairline between two rows of a group starts under the rows' words.
void main() {
  Future<double> indentOf(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(body: card),
      ),
    );
    return tester.widget<Divider>(find.byType(Divider)).indent!;
  }

  const rows = [SizedBox(height: 44), SizedBox(height: 44)];

  testWidgets('rows with a glyph: past the glyph\'s well', (tester) async {
    expect(
      await indentOf(tester, const SettingsGroupCard(children: rows)),
      AppSpacing.lg + 36 + AppSpacing.lg,
    );
  });

  testWidgets('rows of choices, with no glyph: where their words start', (
    tester,
  ) async {
    expect(
      await indentOf(tester, const SettingsGroupCard.choices(children: rows)),
      AppSpacing.lg,
    );
  });
}

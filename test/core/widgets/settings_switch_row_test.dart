import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/settings_switch_row.dart';

/// A setting that is on or off: one stop for a screen reader.
void main() {
  Future<List<bool>> pump(
    WidgetTester tester, {
    bool value = false,
    bool held = false,
    bool busy = false,
  }) async {
    final flips = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SettingsSwitchRow(
            icon: Icons.priority_high_rounded,
            title: 'Needs you',
            description: 'When a download is stuck.',
            note: (text: 'System permission: granted', tone: null),
            value: value,
            onChanged: held ? null : flips.add,
            busy: busy,
          ),
        ),
      ),
    );
    return flips;
  }

  testWidgets('the words and the switch are one node, which a tap flips', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final flips = await pump(tester);
    final node = tester.getSemantics(find.byType(SettingsSwitchRow));
    expect(
      node.label,
      allOf(
        contains('Needs you'),
        contains('When a download is stuck.'),
        contains('System permission: granted'),
      ),
    );
    expect(
      node,
      isSemantics(hasToggledState: true, isToggled: false, hasTapAction: true),
    );
    await tester.tap(find.byType(Switch));
    expect(flips, [true]);
    semantics.dispose();
  });

  testWidgets('held by another setting, the switch shows where it stands', (
    tester,
  ) async {
    final flips = await pump(tester, value: true, held: true);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    expect(flips, isEmpty);
  });

  testWidgets('busy, a spinner stands where the switch is', (tester) async {
    await pump(tester, busy: true);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

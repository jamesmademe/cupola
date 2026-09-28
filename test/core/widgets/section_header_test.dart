import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/section_header.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget header, double scale) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              // A header sits in a list, which hands it unbounded height.
              body: ListView(children: [SizedBox(width: 360, child: header)]),
            ),
          ),
        ),
      );

  group('SectionHeader above 1.4x', () {
    testWidgets('the implicit chevron stays on the title line', (tester) async {
      // The chevron was counted as a trailing control, so a plain tappable
      // header stacked and left the glyph alone on a line of its own.
      await pump(
        tester,
        SectionHeader(title: 'Needs attention', onTap: () {}),
        1.6,
      );

      final title = tester.getRect(find.text('Needs attention'));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(chevron.left, greaterThan(title.left));
      expect(chevron.top, lessThan(title.bottom));
      expect(chevron.bottom, greaterThan(title.top));
    });

    testWidgets('a real trailing control still stacks under the title', (
      tester,
    ) async {
      await pump(
        tester,
        SectionHeader.action(
          title: 'Wanted',
          trailing: OutlinedButton(
            onPressed: () {},
            child: const Text('Search all'),
          ),
        ),
        1.5,
      );

      final title = tester.getRect(find.text('Wanted'));
      final button = tester.getRect(find.byType(OutlinedButton));
      expect(button.top, greaterThanOrEqualTo(title.bottom));
    });
  });
}

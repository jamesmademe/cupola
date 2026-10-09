import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';

Future<void> _pumpLink(WidgetTester tester, {required double textScale}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 358,
              child: ActivitySlabLink(
                label: 'All 120 requests',
                meta: '2 processing · 1 declined',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ActivitySlabLink', () {
    testWidgets('beside its label, the count keeps to one line', (
      tester,
    ) async {
      await _pumpLink(tester, textScale: 1);

      final label = tester.getRect(find.text('All 120 requests'));
      final count = tester.getRect(find.text('2 processing · 1 declined'));
      expect(count.left, greaterThan(label.left));
      expect(count.top, lessThan(label.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 200% the count goes under the label, whole', (
      tester,
    ) async {
      await _pumpLink(tester, textScale: 2);

      final label = tester.getRect(find.text('All 120 requests'));
      final count = tester.getRect(find.text('2 processing · 1 declined'));
      expect(count.top, greaterThanOrEqualTo(label.bottom));
      expect(count.left, label.left);
      final text = tester.widget<Text>(find.text('2 processing · 1 declined'));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull);
      expect(
        tester.getSize(find.byType(ActivitySlabLink)).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'says its label and its counts as one sentence, without the dot',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpLink(tester, textScale: 2);

        expect(
          find.bySemanticsLabel('All 120 requests, 2 processing, 1 declined'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/presentation/widgets/balanced_columns.dart';

/// The Home's two columns, evened by what the modules draw.
void main() {
  Widget box(String name, double height) =>
      SizedBox(key: ValueKey(name), height: height);

  Future<void> pump(
    WidgetTester tester, {
    required List<Widget> main,
    required List<Widget> side,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1200,
            child: BalancedColumns(main: main, side: side),
          ),
        ),
      ),
    );
  }

  Rect at(WidgetTester tester, String name) =>
      tester.getRect(find.byKey(ValueKey(name)));

  testWidgets('balanced columns stay as the person put them, split 7 to 5', (
    tester,
  ) async {
    await pump(
      tester,
      main: [box('featured', 400), box('arrived', 200)],
      side: [box('comingUp', 250), box('downloads', 300)],
    );
    expect(at(tester, 'featured').left, 0);
    expect(at(tester, 'featured').width, 700);
    expect(at(tester, 'arrived').top, 400);
    expect(at(tester, 'comingUp').left, 700);
    expect(at(tester, 'comingUp').width, 500);
    expect(at(tester, 'downloads').top, 250);
  });

  testWidgets('modules that drew nothing do not hold a column up: the taller '
      'one\'s last module crosses', (tester) async {
    await pump(
      tester,
      // The carousel and the arrivals had nothing to say.
      main: [
        box('featured', 0),
        box('continue', 150),
        box('arrived', 0),
        box('nowPlaying', 150),
      ],
      side: [box('comingUp', 300), box('downloads', 500), box('requests', 450)],
    );
    // Requests crosses to the left, under what was already there.
    expect(at(tester, 'requests').left, 0);
    expect(at(tester, 'requests').top, 300);
    expect(at(tester, 'downloads').left, 700);
    expect(tester.getSize(find.byType(BalancedColumns)).height, 800);
  });

  testWidgets('a column keeps one module of its own', (tester) async {
    await pump(
      tester,
      main: [box('continue', 100)],
      side: [box('downloads', 900)],
    );
    expect(at(tester, 'downloads').left, 700);
    expect(at(tester, 'continue').left, 0);
  });
}

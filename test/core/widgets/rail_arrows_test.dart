import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/rail_arrows.dart';
import 'package:cupola/core/widgets/section_header.dart';

/// A rail of [count] 100pt tiles in a 400pt window, its heading carrying the
/// arrows.
Widget _rail(int count) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      child: RailArrows(
        builder: (context, controller, arrows) => Column(
          children: [
            SectionHeader(title: 'Arrived', showChevron: false, rail: arrows),
            SizedBox(
              height: 100,
              child: ListView.builder(
                controller: controller,
                scrollDirection: Axis.horizontal,
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(width: 100, child: Text('Tile $i')),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

IconButton _arrow(WidgetTester tester, String which) =>
    tester.widget<IconButton>(find.byKey(ValueKey('rail-arrow-$which')));

double _offset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels;

void main() {
  group('on a desktop', () {
    testWidgets('a rail that runs past the window has both arrows, the first '
        'off at the start', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_rail(10));
      await tester.pumpAndSettle();

      expect(_arrow(tester, 'back').onPressed, isNull);
      expect(_arrow(tester, 'forward').onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('rail-arrow-forward')));
      await tester.pumpAndSettle();
      expect(_offset(tester), 400 * RailArrows.step);
      expect(_arrow(tester, 'back').onPressed, isNotNull);

      // To the end: the second goes off.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('rail-arrow-forward')));
        await tester.pumpAndSettle();
      }
      expect(_offset(tester), 600);
      expect(_arrow(tester, 'forward').onPressed, isNull);
    }, variant: _desktop);

    testWidgets('a rail that fits has none', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_rail(3));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('rail-arrow-back')), findsNothing);
    }, variant: _desktop);

    testWidgets('the arrows are silent and never take the focus', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_rail(10));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Back|Forward')), findsNothing);
      final focus = Focus.of(
        tester.element(find.byKey(const ValueKey('rail-arrow-forward'))),
      );
      expect(focus.canRequestFocus, isFalse);
      handle.dispose();
    }, variant: _desktop);
  });

  testWidgets('a touch screen has none, until a mouse is there', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_rail(10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rail-arrow-forward')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 300));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rail-arrow-forward')), findsOneWidget);
  });
}

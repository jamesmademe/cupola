import 'dart:ui' show PictureRecorder;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// A tile as the rails draw it: the poster over its caption, one control.
Widget _tile({VoidCallback? onTap}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 104,
        child: PressableScale(
          onTap: onTap,
          semanticLabel: 'Sprite Fright',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 104,
                height: 156,
                child: ContentCard(imageUrl: null),
              ),
              Text('Sprite Fright'),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// How far the poster stands off its place.
double _lift(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(ContentCard),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .getTranslation()
    .y;

/// The painters over the poster and around the control, by name.
List<String> _rings(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.foregroundPainter case final painter?)
      painter.runtimeType.toString(),
];

void main() {
  testWidgets('a mouse over a tile gets the pointing hand, and the poster '
      'rises', (tester) async {
    await tester.pumpWidget(_tile(onTap: () {}));
    expect(_lift(tester), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ContentCard)));
    await tester.pumpAndSettle();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
    expect(_lift(tester), -AppAnimation.hoverLift);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(_lift(tester), 0);
  });

  testWidgets('a tile that cannot act neither rises nor points', (
    tester,
  ) async {
    await tester.pumpWidget(_tile());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ContentCard)));
    await tester.pumpAndSettle();

    expect(_lift(tester), 0);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      isNot(SystemMouseCursors.click),
    );
  });

  testWidgets('Tab reaches a tile, Enter opens it, and the ring is on the '
      "poster's corner, not around the caption", (tester) async {
    var opened = 0;
    await tester.pumpWidget(_tile(onTap: () => opened++));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_rings(tester), contains('_FocusRing'));
    // The control's own ring stands down for the poster's.
    expect(_rings(tester), contains('_ControlRing'));
    final control = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere(
          (paint) =>
              paint.foregroundPainter.runtimeType.toString() == '_ControlRing',
        );
    final recorder = PictureRecorder();
    final canvas = _CountingCanvas(Canvas(recorder));
    control.foregroundPainter!.paint(canvas, const Size(104, 180));
    expect(canvas.strokes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(opened, 2);
  });

  testWidgets('a control with no poster in it draws the ring itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              onTap: () {},
              child: const SizedBox(width: 200, height: 56),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final control = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere(
          (paint) =>
              paint.foregroundPainter.runtimeType.toString() == '_ControlRing',
        );
    final canvas = _CountingCanvas(Canvas(PictureRecorder()));
    control.foregroundPainter!.paint(canvas, const Size(200, 56));
    expect(canvas.strokes, 1);
  });

  testWidgets('a finger never sees the ring: a tap does not focus', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_tile(onTap: () => opened++));
    await tester.tap(find.byType(ContentCard));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(_rings(tester), isNot(contains('_FocusRing')));
    expect(_lift(tester), 0);
  });
}

/// Counts the strokes a painter draws.
class _CountingCanvas implements Canvas {
  _CountingCanvas(this._inner);

  final Canvas _inner;
  int strokes = 0;

  @override
  void drawRRect(RRect rrect, Paint paint) {
    strokes++;
    _inner.drawRRect(rrect, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

import 'package:flutter/material.dart';

/// A control's own shape, with the keyboard's focus ring drawn [gap] outside
/// it in [color] (`line.focus`).
///
/// Outside, and apart from the control, because the brand book's focus ring
/// is a ring: drawn on the edge of the ink button, the secondary ink would
/// vanish into the ink, and a fill that only changes shade is no ring at all,
/// which is what a filled button had. The ring follows the shape: a rounded
/// superellipse grows its radius with it, so the two curves stay concentric;
/// any other shape is drawn again around the grown rectangle.
///
/// Resolved on `WidgetState.focused` by the button themes
/// ([focusRingShape]); a tap never focuses a button, so a finger never sees
/// it.
@immutable
class FocusRingBorder extends OutlinedBorder {
  const FocusRingBorder(
    this.base, {
    required this.color,
    this.gap = 2,
    this.width = 2,
  });

  /// The control's shape at rest, painted as it always is.
  final OutlinedBorder base;

  final Color color;

  /// Between the control's edge and the ring.
  final double gap;

  /// The ring's stroke.
  final double width;

  @override
  BorderSide get side => base.side;

  @override
  EdgeInsetsGeometry get dimensions => base.dimensions;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      base.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      base.getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    base.paint(canvas, rect, textDirection: textDirection);
    final out = gap + width / 2;
    final ring = switch (base) {
      final RoundedSuperellipseBorder shape => shape.copyWith(
        borderRadius: shape.borderRadius.add(BorderRadius.circular(out)),
        side: BorderSide.none,
      ),
      final RoundedRectangleBorder shape => shape.copyWith(
        borderRadius: shape.borderRadius.add(BorderRadius.circular(out)),
        side: BorderSide.none,
      ),
      _ => base.copyWith(side: BorderSide.none),
    };
    canvas.drawPath(
      ring.getOuterPath(rect.inflate(out), textDirection: textDirection),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  FocusRingBorder copyWith({BorderSide? side}) => FocusRingBorder(
    base.copyWith(side: side),
    color: color,
    gap: gap,
    width: width,
  );

  @override
  FocusRingBorder scale(double t) => FocusRingBorder(
    base.scale(t) as OutlinedBorder,
    color: color,
    gap: gap * t,
    width: width * t,
  );

  @override
  bool operator ==(Object other) =>
      other is FocusRingBorder &&
      other.base == base &&
      other.color == color &&
      other.gap == gap &&
      other.width == width;

  @override
  int get hashCode => Object.hash(base, color, gap, width);
}

/// [shape] at rest, and with the focus ring in [ring] while focused: the
/// value a button theme's `shape` takes.
WidgetStateProperty<OutlinedBorder> focusRingShape(
  OutlinedBorder shape, {
  required Color ring,
}) => WidgetStateProperty.resolveWith(
  (states) => states.contains(WidgetState.focused)
      ? FocusRingBorder(shape, color: ring)
      : shape,
);

/// The same ring around a shape that is not a button's: [rect] with corners
/// [radius], the ring [gap] outside it with its curve concentric. For a tile
/// or a poster that takes the keyboard's focus without a button theme.
void paintFocusRing(
  Canvas canvas,
  Rect rect, {
  required BorderRadius radius,
  required Color color,
  double gap = 2,
  double width = 2,
}) {
  final out = gap + width / 2;
  canvas.drawRRect(
    radius
        .add(BorderRadius.circular(out))
        .resolve(TextDirection.ltr)
        .toRRect(rect.inflate(out)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color,
  );
}

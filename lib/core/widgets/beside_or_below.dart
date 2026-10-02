import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A sentence with its verbs beside it, or under it once beside them it would
/// be narrower than [minLead]: the layout of a fault line (`FaultBand`,
/// `InlineErrorRetry`).
///
/// Beside, [lead] takes what [trailing] leaves and the two centre on each
/// other. Under, [lead] keeps the whole width and [trailing] follows [gap]
/// below it at the trailing edge, where it sat beside, so the verbs stay in
/// one place whatever the text size; a `Wrap` there breaks onto a second line
/// if even the whole width is too narrow.
///
/// A large text size, or a long remedy on a phone, used to leave the sentence
/// a column of two or three letters that broke inside every word. [minLead]
/// is measured in the sentence's own type ([sentenceMeasure]), so text at
/// 200% on a phone always puts the verbs under it.
class BesideOrBelow
    extends SlottedMultiChildRenderObjectWidget<BesideOrBelowSlot, RenderBox> {
  const BesideOrBelow({
    super.key,
    required this.lead,
    required this.trailing,
    required this.minLead,
    required this.gap,
  });

  /// The sentence, with its glyph.
  final Widget lead;

  /// The verbs.
  final Widget trailing;

  /// The narrowest [lead] goes beside [trailing].
  final double minLead;

  /// Between [lead] and [trailing], beside or under.
  final double gap;

  /// Sixteen of a sentence's [em], about thirty characters a line: narrower,
  /// and a sentence reads a word at a time.
  static double sentenceMeasure(double em) => 16 * em;

  @override
  Iterable<BesideOrBelowSlot> get slots => BesideOrBelowSlot.values;

  @override
  Widget childForSlot(BesideOrBelowSlot slot) => switch (slot) {
    BesideOrBelowSlot.lead => lead,
    BesideOrBelowSlot.trailing => trailing,
  };

  @override
  RenderBesideOrBelow createRenderObject(BuildContext context) =>
      RenderBesideOrBelow(minLead: minLead, gap: gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBesideOrBelow renderObject,
  ) {
    renderObject
      ..minLead = minLead
      ..gap = gap;
  }
}

/// The two places of a [BesideOrBelow].
enum BesideOrBelowSlot { lead, trailing }

/// The render object of [BesideOrBelow].
class RenderBesideOrBelow extends RenderBox
    with SlottedContainerRenderObjectMixin<BesideOrBelowSlot, RenderBox> {
  RenderBesideOrBelow({required double minLead, required double gap})
    : _minLead = minLead,
      _gap = gap;

  double get minLead => _minLead;
  double _minLead;
  set minLead(double value) {
    if (value == _minLead) return;
    _minLead = value;
    markNeedsLayout();
  }

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  RenderBox get _lead => childForSlot(BesideOrBelowSlot.lead)!;
  RenderBox get _trailing => childForSlot(BesideOrBelowSlot.trailing)!;

  double get _verbs => _trailing.getMaxIntrinsicWidth(double.infinity);

  /// The one decision: what the verbs at their natural width leave the
  /// sentence, against [minLead].
  bool below(double width) => width - _verbs - _gap < _minLead;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _lead.getMinIntrinsicWidth(double.infinity),
    _trailing.getMinIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _lead.getMaxIntrinsicWidth(double.infinity) + _gap + _verbs;

  @override
  double computeMinIntrinsicHeight(double width) => _height(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _height(width);

  double _height(double width) {
    if (!width.isFinite) {
      return math.max(
        _lead.getMaxIntrinsicHeight(double.infinity),
        _trailing.getMaxIntrinsicHeight(double.infinity),
      );
    }
    if (below(width)) {
      return _lead.getMaxIntrinsicHeight(width) +
          _gap +
          _trailing.getMaxIntrinsicHeight(width);
    }
    final verbs = _verbs;
    return math.max(
      _lead.getMaxIntrinsicHeight(width - verbs - _gap),
      _trailing.getMaxIntrinsicHeight(verbs),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (below(width)) {
      final lead = _lead.getDryLayout(BoxConstraints.tightFor(width: width));
      final verbs = _trailing.getDryLayout(BoxConstraints(maxWidth: width));
      return constraints.constrain(
        Size(width, lead.height + _gap + verbs.height),
      );
    }
    final verbs = _trailing.getDryLayout(BoxConstraints(maxWidth: width));
    final lead = _lead.getDryLayout(
      BoxConstraints.tightFor(width: width - verbs.width - _gap),
    );
    return constraints.constrain(
      Size(width, math.max(lead.height, verbs.height)),
    );
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final lead = _lead;
    final trailing = _trailing;
    final leadData = lead.parentData! as BoxParentData;
    final trailingData = trailing.parentData! as BoxParentData;

    if (below(width)) {
      lead.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      trailing.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      leadData.offset = Offset.zero;
      trailingData.offset = Offset(
        width - trailing.size.width,
        lead.size.height + _gap,
      );
      size = constraints.constrain(
        Size(width, lead.size.height + _gap + trailing.size.height),
      );
      return;
    }

    trailing.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    lead.layout(
      BoxConstraints.tightFor(width: width - trailing.size.width - _gap),
      parentUsesSize: true,
    );
    final height = math.max(lead.size.height, trailing.size.height);
    leadData.offset = Offset(0, (height - lead.size.height) / 2);
    trailingData.offset = Offset(
      width - trailing.size.width,
      (height - trailing.size.height) / 2,
    );
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

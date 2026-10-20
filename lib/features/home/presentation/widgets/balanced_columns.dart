import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The Home's two columns, evened by what the modules actually draw.
///
/// Each module belongs to a column (`HomePlace`): what is happening on the
/// left, what waits on the right. But a module that has nothing to say steps
/// aside and draws nothing, and only layout knows which did: a Home whose
/// carousel and arrivals are empty stood as two short cards beside three long
/// lists. So the columns are laid out, measured, and then, while the taller
/// one's last visible module, moved to the end of the shorter one, brings
/// their heights closer, it moves. Each column keeps the person's order; a
/// column always keeps one module of its own.
///
/// The modules keep their own gutters, so the columns need no gap between
/// them. [mainFlex] to [sideFlex] splits the width.
class BalancedColumns extends MultiChildRenderObjectWidget {
  BalancedColumns({
    super.key,
    required List<Widget> main,
    required List<Widget> side,
    this.mainFlex = 7,
    this.sideFlex = 5,
  }) : mainCount = main.length,
       super(children: [...main, ...side]);

  /// How many of the children start in the main column: the rest start in
  /// the side one.
  final int mainCount;
  final int mainFlex;
  final int sideFlex;

  @override
  RenderBalancedColumns createRenderObject(BuildContext context) =>
      RenderBalancedColumns(
        mainCount: mainCount,
        mainFlex: mainFlex,
        sideFlex: sideFlex,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBalancedColumns renderObject,
  ) {
    renderObject
      ..mainCount = mainCount
      ..mainFlex = mainFlex
      ..sideFlex = sideFlex;
  }
}

class BalancedColumnsParentData extends ContainerBoxParentData<RenderBox> {
  /// Where the child ended up after balancing: true for the side column.
  bool inSide = false;
}

class RenderBalancedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, BalancedColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, BalancedColumnsParentData> {
  RenderBalancedColumns({
    required int mainCount,
    required int mainFlex,
    required int sideFlex,
  }) : _mainCount = mainCount,
       _mainFlex = mainFlex,
       _sideFlex = sideFlex;

  int _mainCount;
  set mainCount(int value) {
    if (value == _mainCount) return;
    _mainCount = value;
    markNeedsLayout();
  }

  int _mainFlex;
  set mainFlex(int value) {
    if (value == _mainFlex) return;
    _mainFlex = value;
    markNeedsLayout();
  }

  int _sideFlex;
  set sideFlex(int value) {
    if (value == _sideFlex) return;
    _sideFlex = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BalancedColumnsParentData) {
      child.parentData = BalancedColumnsParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final mainWidth = (width * _mainFlex / (_mainFlex + _sideFlex))
        .floorToDouble();
    final sideWidth = width - mainWidth;
    double layOut(RenderBox child, bool side) {
      child.layout(
        BoxConstraints.tightFor(width: side ? sideWidth : mainWidth),
        parentUsesSize: true,
      );
      return child.size.height;
    }

    final main = <RenderBox>[];
    final side = <RenderBox>[];
    var index = 0;
    var child = firstChild;
    while (child != null) {
      final inSide = index >= _mainCount;
      layOut(child, inSide);
      (inSide ? side : main).add(child);
      child = childAfter(child);
      index++;
    }

    double heightOf(List<RenderBox> column) =>
        column.fold(0, (sum, child) => sum + child.size.height);
    int visible(List<RenderBox> column) =>
        column.where((child) => child.size.height > 0).length;

    // Bounded: each move takes a module from the taller column, and a column
    // never gives its last visible one.
    for (var moves = 0; moves < main.length + side.length; moves++) {
      final gap = heightOf(side) - heightOf(main);
      final fromSide = gap > 0;
      final from = fromSide ? side : main;
      final to = fromSide ? main : side;
      if (visible(from) < 2) break;
      final candidate = from.lastWhere((child) => child.size.height > 0);
      final oldHeight = candidate.size.height;
      final newHeight = layOut(candidate, !fromSide);
      final newGap = (gap.abs() - oldHeight - newHeight).abs();
      if (newGap >= gap.abs()) {
        layOut(candidate, fromSide);
        break;
      }
      from.remove(candidate);
      to.add(candidate);
    }

    void place(List<RenderBox> column, double x, bool inSide) {
      var y = 0.0;
      for (final child in column) {
        final data = child.parentData! as BalancedColumnsParentData
          ..inSide = inSide
          ..offset = Offset(x, y);
        y += child.size.height;
        assert(data.inSide == inSide);
      }
    }

    place(main, 0, false);
    place(side, mainWidth, true);
    size = constraints.constrain(
      Size(width, math.max(heightOf(main), heightOf(side))),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

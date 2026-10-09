import 'package:flutter/widgets.dart';

import 'package:cupola/core/app_spacing.dart';

/// How far the Home's column stands from the page's edges: nothing on a
/// phone, the reading well's margin on a wider page
/// (`AppBreakpoints.wellInset`).
///
/// The Home's list spans the page and every module sits in the column, but a
/// shelf of posters spans the page and sets its first poster on the column's
/// line ([shelfInsetOf]), so its posters scroll to the page's edge: cut at the
/// column's edge, with nothing beside the cut, a shelf reads as broken.
class HomeWell extends InheritedWidget {
  const HomeWell({super.key, required this.inset, required super.child});

  final double inset;

  static double insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeWell>()?.inset ?? 0;

  /// A shelf's inset: the page's gutter plus the column's margin.
  static double shelfInsetOf(BuildContext context) =>
      AppSpacing.lg + insetOf(context);

  /// [child] in the column.
  static Widget column(BuildContext context, Widget child) {
    final inset = insetOf(context);
    if (inset == 0) return child;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: child,
    );
  }

  @override
  bool updateShouldNotify(HomeWell oldWidget) => oldWidget.inset != inset;
}

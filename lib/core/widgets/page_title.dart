import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';

/// A page's name in the page itself, in the room role (30/31), on Settings
/// and every page pushed over a tab (brand book, *A page's name is in the
/// page*): the bar above holds only the way back and the page's actions
/// ([GlassAppBar.inPage]) and takes the name, small, once this has scrolled
/// under it.
///
/// The first thing in the page's scroll view, so it scrolls away with the
/// page. [summary] says under it, in one line, how things stand (Settings:
/// how many services are set up, and where this device is).
class PageTitle extends StatelessWidget {
  /// The name at the page's own inset, for a scroll view that runs to the
  /// window's edges.
  const PageTitle(this.title, {super.key, this.summary}) : _inset = true;

  /// The name inside a column the page has already inset.
  const PageTitle.flush(this.title, {super.key, this.summary}) : _inset = false;

  final String title;

  /// The line under the name, or null for none. Set in the meta role and the
  /// secondary ink unless it says otherwise.
  final Widget? summary;

  final bool _inset;

  /// How far a page scrolls before its name has gone under the bar, and the
  /// bar says it instead.
  static const double scrolledUnder = 40;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final side = _inset ? AppSpacing.gutter : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, AppSpacing.xs, side, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppType.room.copyWith(color: room.ink)),
          ),
          if (summary case final summary?) ...[
            const SizedBox(height: AppSpacing.s),
            DefaultTextStyle.merge(
              style: AppType.meta.copyWith(color: room.inkSecondary),
              child: summary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether the page's heading ([PageTitle]) has scrolled under the bar: what
/// the bar of a page that names itself in the page ([GlassAppBar.inPage])
/// listens to. `AmbientScaffold` hosts it over its bar and its body.
class PageScrollScope extends InheritedWidget {
  const PageScrollScope({
    super.key,
    required this.headingUnder,
    required super.child,
  });

  final ValueListenable<bool> headingUnder;

  static ValueListenable<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageScrollScope>()?.headingUnder;

  @override
  bool updateShouldNotify(PageScrollScope oldWidget) =>
      headingUnder != oldWidget.headingUnder;
}

/// A body that is not a list (an empty state, a failure, a form that fills
/// the page) under the page's name: the name at the page's inset, the body in
/// the rest.
class TitledBody extends StatelessWidget {
  const TitledBody({
    super.key,
    required this.title,
    this.summary,
    required this.child,
  });

  final String title;
  final Widget? summary;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageTitle(title, summary: summary),
      // A list under the name melts into the room at its edge, as one under
      // a bar does.
      Expanded(child: ScrollEdgeFade(child: child)),
    ],
  );
}

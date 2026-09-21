import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The bar of views belonging to one service.
///
/// **Drawn by the tab's own root page, never by the shell and never as
/// `GlassAppBar.bottom`.** That is not a style preference: a pushed page —
/// a detail, a wizard, a search result — has to hide the bar without leaving
/// the branch it was pushed from, and a bar owned by the shell or bolted onto
/// the app bar cannot be hidden without unmounting the thing that owns it.
/// Each tab root drawing its own is what makes "back returns to the tab you
/// left, scrolled where you left it" buildable at all.
///
/// It is also not a Material [TabBar]. A `TabBar` is driven by a
/// `TabController` holding an index, and these tabs are *router branches*: the
/// selected one is a fact about the current location, and a tap is navigation,
/// not a controller mutation. Wiring a controller alongside the router would
/// give the same state two owners, which is how a bar and a URL come to
/// disagree after a deep link or a back gesture.
class ServiceTabBar extends StatelessWidget {
  /// The service whose views these are — it supplies the accent and the bar.
  final ServiceKey service;

  /// The tab currently showing. Read from the route, not from a controller.
  final ServiceTab current;

  /// Navigate to [tab]. The caller owns the route shape.
  final ValueChanged<ServiceTab> onSelected;

  /// Height of the bar, so a hosted scroll view can reserve it.
  static const double height = 44;

  const ServiceTabBar({
    super.key,
    required this.service,
    required this.current,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = tabsFor(service);
    // TrueNAS. Ten sections are too many for a bar, so it keeps its console —
    // and a console is not an empty bar, so nothing is drawn rather than an
    // empty strip that would read as tabs that failed to load.
    if (tabs == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The accent is walked against the surface the bar sits on: seven of the
    // seventeen are under 3:1 on paper, and this label is the accent carrying
    // ink at its smallest in the whole app.
    final accent = ServiceTheme.onTint(
      service.accent,
      surface: colorScheme.surface,
      tintAlpha: 0,
    );

    return SizedBox(
      height: height,
      // Scrollable, always, and aligned to the start. Eight of the sixteen
      // label sets are wider than the narrowest frame the app draws, so a bar
      // that distributed its tabs would silently squeeze them — and a bar that
      // centred them would put Overview somewhere different on every service.
      //
      // Every tab is built, rather than a lazy list: six children is nothing to
      // lay out, and a tab that has not been built is a tab a screen reader
      // cannot reach. Laziness here would buy no frame time and cost the one
      // audience that cannot scroll the bar to find out what is on it.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          // Stretch, so every cell is the bar's full height and the whole
          // 44pt strip above a label is part of its target.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final tab in tabs) ...[
              if (tab != tabs.first) const SizedBox(width: AppSpacing.xs),
              _Tab(
                tab: tab,
                selected: tab == current,
                accent: accent,
                onTap: () => onSelected(tab),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final ServiceTab tab;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Tab({
    required this.tab,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      selected: selected,
      button: true,
      // The label alone: "Library" reads as the destination, and a screen
      // reader already announces the selected state from the flag above.
      label: tab.label,
      onTap: selected ? null : onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: AppRadius.borderRadiusPill,
          child: ConstrainedBox(
            // The floor for a touch target, even for a two-letter label.
            constraints: const BoxConstraints(minWidth: 44),
            // A Stack rather than a Column so the rule can span exactly the
            // label's own width: inside a horizontally scrolling list there is no
            // width to inherit, so a rule asking for one would be asking for
            // infinity.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    tab.label,
                    style: theme.textTheme.labelLarge!
                        .weight(selected ? FontWeight.w700 : FontWeight.w500)
                        .copyWith(
                          color: selected
                              ? accent
                              : colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                  ),
                ),
                // Drawn only when selected, and nothing shifts when it appears:
                // the rule is positioned rather than laid out in flow.
                if (selected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: AppRadius.borderRadiusPill,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

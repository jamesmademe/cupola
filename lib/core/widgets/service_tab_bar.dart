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

  /// The connection lens, drawn after the name. Header variant only.
  final Widget? lens;

  /// The service's own instruments, at the end of the row. Header variant only.
  final List<Widget> actions;

  final bool _header;

  /// Height of the bar, so a hosted scroll view can reserve it.
  static const double height = 44;

  /// The room light: the service accent over the header's surface, across the
  /// whole band. DESIGN.md's Bounded Light Rule — the room is named by one
  /// bounded, edged surface at 0.12, not by the ambient radial, which sits at
  /// the ceiling measurement allows and cannot say which room this is.
  ///
  /// The rule named the deck strip as that band. Since the tab row became the
  /// service header on a desktop window the deck carries only the fleet, so
  /// the light moved here: this band is the one lit surface on a service page.
  static const double roomLightAlpha = 0.12;

  /// How far up from the band's lower edge the bloom reaches — the 11px
  /// DESIGN.md gives it. Every label, glyph and pill is centred in the 44pt
  /// row and ends above it, so no text is ever drawn over the bloom.
  static const double bloomHeight = 11;

  /// The bloom's strength at the band's lower edge. **Solved, not chosen.**
  ///
  /// DESIGN.md writes 0.55, which it set for the deck — a band with nothing in
  /// its lower 11px. This band has the selected tab's 2px rule there, drawn in
  /// the same accent: at 0.55 the rule falls to 2.08:1 against the bloom under
  /// it (NZBGet, dark) and stops reading as the selection. 0.30 is the
  /// strongest bloom at which every one of the sixteen tabbed accents keeps
  /// its rule at 3:1 or better in both themes (floor 3.10:1, Transmission,
  /// light) — the bloom gave way, not the indicator.
  static const double bloomAlpha = 0.30;

  /// The opaque surface every control on the header sits on: the room light
  /// composited over the scheme's surface. Anything drawn on the band resolves
  /// its ink against this, never against the bare surface.
  static Color headerSurfaceOf(ColorScheme colorScheme, ServiceKey service) =>
      Color.alphaBlend(
        service.accent.withValues(alpha: roomLightAlpha),
        colorScheme.surface,
      );

  const ServiceTabBar({
    super.key,
    required this.service,
    required this.current,
    required this.onSelected,
  }) : lens = null,
       actions = const [],
       _header = false;

  /// The bar as the service's whole header — the desktop window's variant.
  ///
  /// On a desktop window the chrome already names the room (the breadcrumb is
  /// the URL) and the deck carries the fleet, so the phone's band above this
  /// bar — back, name, one action — would be a third strip saying what two
  /// have said. This row takes over what the band had that nobody else says:
  /// the service's glyph and name, its [lens], and its [actions]. One 44pt row
  /// instead of 100pt of band and bar.
  const ServiceTabBar.header({
    super.key,
    required this.service,
    required this.current,
    required this.onSelected,
    this.lens,
    this.actions = const [],
  }) : _header = true;

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
    // ink at its smallest in the whole app. On the header that surface is the
    // lit band, so the walk is told about the room light under it.
    final accent = ServiceTheme.onTint(
      service.accent,
      surface: colorScheme.surface,
      tintAlpha: _header ? roomLightAlpha : 0,
    );

    // Scrollable, always, and aligned to the start. Eight of the sixteen
    // label sets are wider than the narrowest frame the app draws, so a bar
    // that distributed its tabs would silently squeeze them — and a bar that
    // centred them would put Overview somewhere different on every service.
    //
    // Every tab is built, rather than a lazy list: six children is nothing to
    // lay out, and a tab that has not been built is a tab a screen reader
    // cannot reach. Laziness here would buy no frame time and cost the one
    // audience that cannot scroll the bar to find out what is on it.
    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: _header ? AppSpacing.sm : AppSpacing.lg,
      ),
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
    );

    if (!_header) return SizedBox(height: height, child: strip);

    final surface = headerSurfaceOf(colorScheme, service);

    // Opaque, not glass. The band is the one lit surface on the page and its
    // ink is measured against it; a translucent band would put whatever
    // scrolled under it into that measurement. No accent border either: the
    // selected tab's rule already draws the accent edge, and a second accent
    // line along the band would read as a second selection.
    return ServiceBandSurface(
      color: surface,
      child: SizedBox(
        key: const ValueKey('service-header-band'),
        height: height,
        child: ColoredBox(
          color: surface,
          child: Stack(
            children: [
              // Painted before the row, so the tabs — and the selected tab's
              // rule, which sits in this zone — are drawn crisp above it.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bloomHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('service-header-bloom'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          service.accent.withValues(alpha: 0),
                          service.accent.withValues(alpha: bloomAlpha),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.lg),
                    _Identity(service: service, surface: surface),
                    ?lens,
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 1,
                      height: 20,
                      color: colorScheme.outlineVariant,
                    ),
                    // The tabs give way before the identity or the instruments
                    // do: they scroll, and a clipped name or a missing action
                    // does not.
                    Expanded(child: strip),
                    ...actions,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The surface a service header's controls are drawn on.
///
/// The header's lens and actions are built by whoever hosts the header and
/// passed in as widgets, so they cannot be handed the lit band's colour as an
/// argument; they read it here instead. Outside a header — the phone's band —
/// there is no room light and the answer is the scheme's own surface, which is
/// what those controls resolved against before.
///
/// A plain [InheritedWidget] on purpose, not a [Theme] override: a sheet or a
/// menu opened from the header captures the inherited *theme*, and a scheme
/// whose surface had been swapped for the lit band would tint the sheet too.
class ServiceBandSurface extends InheritedWidget {
  const ServiceBandSurface({
    super.key,
    required this.color,
    required super.child,
  });

  /// The opaque composite the controls sit on.
  final Color color;

  /// The band surface over [context], or the scheme's surface when there is no
  /// header above it.
  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServiceBandSurface>()?.color ??
      Theme.of(context).colorScheme.surface;

  @override
  bool updateShouldNotify(ServiceBandSurface oldWidget) =>
      color != oldWidget.color;
}

/// The service's glyph and name at the start of the header row.
///
/// The name is the page's heading — on a desktop window it is the only place
/// the service's name is set as one, since the band that carried it is gone.
class _Identity extends StatelessWidget {
  const _Identity({required this.service, required this.surface});

  final ServiceKey service;

  /// The lit band the tile sits on — the tile's tint composites over it.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const tintAlpha = 0.14;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: service.accent.withValues(alpha: tintAlpha),
              borderRadius: BorderRadius.circular(AppRadius.sm - 1),
              border: Border.all(color: service.accent.withValues(alpha: 0.4)),
            ),
            child: Icon(
              service.icon,
              size: 14,
              color: ServiceTheme.onTint(
                service.accent,
                surface: surface,
                tintAlpha: tintAlpha,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        // Capped rather than flexible: a flexible name would take a share of
        // the row's free space and strand the actions short of its end. Past
        // the cap the name ellipsizes and the tabs keep scrolling.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Semantics(
            header: true,
            child: Text(
              service.title,
              key: ValueKey('service-bar-title-${service.routeParam}'),
              style: AppTheme.rowTitle(
                theme.brightness,
              ).copyWith(color: colorScheme.onSurface),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
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
                        .weight(selected ? FontWeight.w600 : FontWeight.w500)
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

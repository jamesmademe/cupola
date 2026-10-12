import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The bar of views belonging to one service.
///
/// **Drawn by the tab's own root page, never by the shell and never as
/// `GlassAppBar.bottom`.** That is not a style preference. A pushed page
/// (a detail, a wizard, a search result) has to hide the bar without leaving
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
  /// The service whose views these are: it supplies the tabs and the mark.
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

  /// The room light across the desktop header band: the lamp over the
  /// header's surface. A service room has no artwork, so it is lit by the
  /// neutral lamp (`ServiceKey.accent` is the lamp for every service), and the
  /// band, the one lit surface on a service page, says "a room" without saying
  /// "whose" in a hue: the mark and the name beside it say that.
  static const double roomLightAlpha = 0.12;

  /// How far up from the band's lower edge the bloom reaches. Every label,
  /// glyph and pill is centred in the 44pt row and ends above it, so no text
  /// is ever drawn over the bloom.
  static const double bloomHeight = 11;

  /// The bloom's strength at the band's lower edge: the lamp at 0.30, a soft
  /// floor of light under the row. It was solved against a 2px accent rule
  /// drawn in the same zone; the selection is a pill now and sits above it.
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

  /// The bar as the service's whole header: the desktop window's variant.
  ///
  /// On a desktop window the chrome already names the room (the breadcrumb is
  /// the URL) and the deck carries the fleet, so the phone's band above this
  /// bar (back, name, one action) would be a third strip saying what two
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
    // TrueNAS. Ten sections are too many for a bar, so it keeps its console:
    // and a console is not an empty bar, so nothing is drawn rather than an
    // empty strip that would read as tabs that failed to load.
    if (tabs == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Scrollable, always, and aligned to the start. Eight of the sixteen
    // label sets are wider than the narrowest frame the app draws, so a bar
    // that distributed its tabs would silently squeeze them, and a bar that
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
    // scrolled under it into that measurement. No edge either: the selected
    // tab's pill already marks the row, and a line along the band would read
    // as a second selection.
    return ServiceBandSurface(
      color: surface,
      child: SizedBox(
        key: const ValueKey('service-header-band'),
        height: height,
        child: ColoredBox(
          color: surface,
          child: Stack(
            children: [
              // Painted before the row, so the tabs are drawn crisp above it.
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
                    _Identity(service: service),
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
/// argument; they read it here instead. Outside a header, the phone's band,
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
/// The name is the page's heading. On a desktop window it is the only place
/// the service's name is set as one, since the band that carried it is gone.
///
/// The mark is the brand book's lit tile: the room's strong fill with an edge and the glyph
/// in the primary ink, a step brighter than a mark in a list, and no hue: the
/// identity is the shape and the name.
class _Identity extends StatelessWidget {
  const _Identity({required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final room = CupolaRoom.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: room.fillStrong,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm2),
              border: Border.all(color: room.edge),
            ),
            child: Icon(service.icon, size: 14, color: colorScheme.onSurface),
          ),
        ),
        const SizedBox(width: AppSpacing.row),
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

/// One tab, the brand book's way: the selected one is the room's strong fill under the
/// primary ink, the rest the tertiary ink on nothing, never the service's
/// colour, the same pill the phone's bar and the desktop rail draw.
class _Tab extends StatelessWidget {
  final ServiceTab tab;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({required this.tab, required this.selected, required this.onTap});

  /// Height of the selected pill inside the 44pt cell: the brand book's chip height, with
  /// the cell's full height still the target.
  static const double pillHeight = 36;

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
            // A Stack rather than a Column so the selected pill can span exactly
            // the label's own width: inside a horizontally scrolling list there
            // is no width to inherit, so a mark asking for one would be asking
            // for infinity.
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Drawn only when selected, and nothing shifts when it appears:
                // the pill is positioned behind the label rather than laid out
                // in flow, so the cell is the same width either way.
                if (selected)
                  Positioned(
                    left: 0,
                    right: 0,
                    child: Container(
                      key: const ValueKey('service-tab-pill'),
                      height: pillHeight,
                      decoration: BoxDecoration(
                        color: CupolaRoom.of(context).fillStrong,
                        borderRadius: AppRadius.borderRadiusPill,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    tab.label,
                    // Chrome, like the phone's bar: the label grows with the
                    // reading size to the same 1.3x and no further, so it
                    // stays whole in the 44pt row every hosted page reserves.
                    // At 200% the row cut "Library" below its baseline.
                    textScaler: FloatingNavBarMetrics.effectiveTextScaler(
                      context,
                    ),
                    style: theme.textTheme.labelLarge!
                        .weight(selected ? FontWeight.w600 : FontWeight.w500)
                        .copyWith(
                          color: selected
                              ? colorScheme.onSurface
                              : CupolaThemeColors.of(context).dimText,
                        ),
                    maxLines: 1,
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

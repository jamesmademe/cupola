import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_breadcrumb.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// The window's top strip: one interior, three shells.
///
/// The only part of the app that knows which operating system it is running on,
/// and it may only use that knowledge for three things — where the window
/// buttons go, how tall the strip is, and which modifier the labels print.
/// Colour, type, spacing, icons and motion are never per-OS, and a change here
/// that touches any of them is a bug however good it looks on one platform.
///
/// The strip is also the window's *title*: the breadcrumb is the title, never
/// duplicated elsewhere, which is why the crumbs are links and not a label.
class WindowChrome extends ConsumerWidget {
  const WindowChrome({super.key, required this.inspectorOpen});

  /// Drives the inspector chip's tone. Passed rather than watched so the strip
  /// has exactly one reason to rebuild that is not its own.
  final bool inspectorOpen;

  /// The drawn height. Same on all three platforms: the OS decides where its
  /// buttons sit, not how much room our chrome takes.
  static const double height = 44;

  /// The compact window's strip. Six points shorter, and its chips lose their
  /// labels rather than their tone — the shortcut stays, because the strip is
  /// the only place a pointer-only user meets it, and the tooltip still says
  /// the whole name.
  static const double compactHeight = 38;

  static double heightFor({required bool compact}) =>
      compact ? compactHeight : height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Width alone, like [WindowDragStrip]: the strip only ever paints inside a
    // desktop window, so the platform half of the shell test adds nothing.
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact;
    final location = GoRouterState.of(context).uri.path;
    final crumbs = ShellBreadcrumb.of(location);
    final lens = _lensFor(ref, location);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Window chrome',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: SizedBox(
          height: heightFor(compact: compact),
          // The whole strip is a drag region, and the buttons inside it still
          // win: they are hit-tested first, so the drag only starts on the
          // background between them.
          child: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  SizedBox(width: DesktopWindow.leadingButtonGutter),
                  Expanded(child: _Breadcrumb(crumbs: crumbs)),
                  if (lens != null) ...[
                    _ChromeChip(
                      compact: compact,
                      label: 'Lens: ${lens.label}',
                      icon: Icons.dns_outlined,
                      on: true,
                      tooltip:
                          'Showing ${lens.service.title} · ${lens.label}. '
                          'Change it from the deck.',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  _ChromeChip(
                    compact: compact,
                    label: 'Refresh all',
                    shortcut: ShellShortcuts.refreshAll,
                    icon: Icons.refresh_rounded,
                    onPressed: () =>
                        Actions.invoke(context, const RefreshAllIntent()),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ChromeChip(
                    compact: compact,
                    label: 'Inspector',
                    shortcut: ShellShortcuts.inspector,
                    icon: Icons.insights_rounded,
                    on: inspectorOpen,
                    onPressed: () =>
                        Actions.invoke(context, const ToggleInspectorIntent()),
                  ),
                  if (DesktopWindow.drawsOwnButtons) ...[
                    const SizedBox(width: AppSpacing.md),
                    const _CaptionButtons(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The instance the current service is being viewed through, if it has a name.
  ///
  /// Nothing is shown for a single-instance service: an unnamed instance has no
  /// label to print, and a chip reading `Lens: Radarr` while the breadcrumb
  /// already says Radarr is furniture. This is the same "you do not pay for the
  /// fold until you need it" rule the app bar badge follows.
  ({ServiceKey service, String label})? _lensFor(
    WidgetRef ref,
    String location,
  ) {
    final crumbSegments = Uri.parse(location).pathSegments;
    if (crumbSegments.length < 2) return null;
    final service = ServiceKey.values.firstWhere(
      (s) => s.routeParam == crumbSegments[1],
      orElse: () => ServiceKey.seerr,
    );
    if (service.routeParam != crumbSegments[1]) return null;
    final instance = ref.watch(activeInstanceProvider(service));
    final label = instance?.label.trim() ?? '';
    if (label.isEmpty) return null;
    return (service: service, label: label);
  }
}

/// The window's obligations, for a screen the shell does not host.
///
/// Onboarding gates the shell, and a handful of flows live above it on the root
/// navigator — so those screens have no [WindowChrome], and the window's three
/// jobs have to be done by something. This is that something, and annotation
/// `onb1` is explicit that it is load-bearing rather than decoration:
///
///  * on **Windows and Linux** it is the only thing that can move a frameless
///    window, and the only place its caption buttons can be — without it the
///    window cannot be moved and, worse, cannot be closed;
///  * on **macOS** it reserves the traffic-light gutter, so AppKit's buttons
///    have somewhere to sit that is not on top of the beat. It used to render
///    nothing at all here (the old guard bailed on `!drawsOwnButtons`, which is
///    exactly the Mac), so the onboarding walk drew its content under the
///    lights;
///  * on **all three** it carries the trail. Not a window *title* — the Chrome
///    sheet forbids one — but the same breadcrumb the shell prints everywhere
///    else, so the strip above a beat is recognisably the strip above a page.
///
/// Renders nothing on a phone, which has no window to move and no gutter to
/// reserve.
///
/// [trail] is plain strings rather than [Crumb]s, and that is the difference
/// between this strip and the shell's: these crumbs point nowhere. Onboarding
/// gates the shell, so there is no `/dashboard` to send someone to, and a
/// clickable crumb that navigates into a locked app is worse than a label.
class WindowDragStrip extends StatelessWidget {
  const WindowDragStrip({super.key, this.trail = const [kAppName, 'Setup']});

  /// The breadcrumb, outermost first. Defaults to onboarding's, since the setup
  /// walk is the only flow above the shell today; a second one passes its own
  /// rather than teaching this widget about routes it cannot reach.
  final List<String> trail;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.isSupported) return const SizedBox.shrink();
    // Width alone, not [AppBreakpoints.isCompactDesktop]: a window narrow
    // enough for the phone layout still carries this strip, and it is the
    // narrowest window there is, not a full-height one.
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact;

    return SizedBox(
      // The shell's own heights, through the shell's own helper: 44 full, 38
      // compact. A strip that agreed with the shell by coincidence would stop
      // agreeing the first time one of the two numbers moved.
      height: WindowChrome.heightFor(compact: compact),
      child: DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              // Zero everywhere but macOS, where it is the measured width of
              // the traffic lights plus the design's gap after them.
              SizedBox(width: DesktopWindow.leadingButtonGutter),
              Expanded(
                child: _Breadcrumb(
                  crumbs: [
                    for (final label in trail) (label: label, location: null),
                  ],
                  // 11px dim throughout, per `onb1`. The shell's trail sets its
                  // leaf in onSurface because that leaf is where you are and
                  // the others are links; nothing here is a link, so nothing
                  // here earns the emphasis.
                  size: 11,
                  dim: true,
                ),
              ),
              if (DesktopWindow.drawsOwnButtons) ...[
                const SizedBox(width: AppSpacing.md),
                const _CaptionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The trail, and therefore the window title.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs, this.size = 12, this.dim = false});

  final List<Crumb> crumbs;

  /// 12 in the shell's chrome, 11 on the drag strip above a gated flow.
  final double size;

  /// Whether the whole trail prints in the dim tone, leaf included.
  ///
  /// The shell's trail says where you *are* by giving the leaf the full ink and
  /// the ancestors the dim one. A trail whose crumbs are not links has no such
  /// distinction to draw, so it prints as one dim line rather than inventing an
  /// emphasis that means nothing.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final crumb = crumbs[i];
      final isLast = i == crumbs.length - 1;
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 13,
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        );
      }
      final text = Text(
        crumb.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.chrome(
          context,
          size: size,
          weight: isLast && !dim ? FontWeight.w600 : FontWeight.w500,
          color: isLast && !dim
              ? colorScheme.onSurface
              : CupolaThemeColors.of(context).dimText,
        ),
      );
      children.add(
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: crumb.location == null || isLast
                ? text
                : _CrumbLink(location: crumb.location!, child: text),
          ),
        ),
      );
    }
    return Semantics(
      // The trail spoken as one sentence: three separate labels with chevrons
      // between them is four announcements for one place.
      label: crumbs.map((c) => c.label).join(', '),
      excludeSemantics: true,
      child: Row(children: children),
    );
  }
}

/// An ancestor crumb: a real control, because the title is the navigation.
class _CrumbLink extends StatefulWidget {
  const _CrumbLink({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_CrumbLink> createState() => _CrumbLinkState();
}

class _CrumbLinkState extends State<_CrumbLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => GoRouter.of(context).go(widget.location),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: CupolaThemeColors.of(context).dimText,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A 28pt chip in the strip: label, optional shortcut, and whether it is on.
///
/// It is a control, so it takes the 12dp interactive radius and not full
/// radius, which in this system means a tag or a piece of metadata. It keeps
/// that shape when it is on: the room's strong fill under the primary ink
/// marks it, and the shape stays the same when it is toggled.
///
/// Monochrome, like the rest of the chrome: *on* is the selected pill of the
/// tab bar and the rail, never a section's or a service's colour and never a
/// status tone. The inspector chip is on while the pane is open; the lens chip
/// is on for as long as it is shown, since it names a choice in force.
class _ChromeChip extends StatefulWidget {
  const _ChromeChip({
    required this.label,
    this.compact = false,
    this.shortcut,
    this.icon,
    this.on = false,
    this.onPressed,
    this.tooltip,
  });

  final String label;

  /// In a compact window the label goes and the glyph plus the shortcut stay.
  final bool compact;
  final String? shortcut;
  final IconData? icon;
  final bool on;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<_ChromeChip> createState() => _ChromeChipState();
}

class _ChromeChipState extends State<_ChromeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final on = widget.on;
    final labelled = !widget.compact || widget.icon == null;
    final chip = Container(
      height: widget.compact ? 26 : 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: on
            ? CupolaRoom.of(context).fillStrong
            : (_hovered ? colorScheme.onSurface.withValues(alpha: 0.06) : null),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 14,
              color: on ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          if (labelled)
            Text(
              widget.label,
              style: AppTheme.chrome(
                context,
                size: 11,
                weight: FontWeight.w600,
                color: on
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.shortcut != null) ...[
            SizedBox(width: labelled ? 6 : 4),
            Text(
              widget.shortcut!,
              style: AppTheme.chrome(
                context,
                size: 11,
                color: CupolaThemeColors.of(context).dimText,
              ).mono.tabular,
            ),
          ],
        ],
      ),
    );

    final semanticLabel = widget.shortcut == null
        ? widget.label
        : '${widget.label}, ${widget.shortcut}';
    final control = widget.onPressed == null
        ? Semantics(label: semanticLabel, excludeSemantics: true, child: chip)
        : TextButton(
            onPressed: widget.onPressed,
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              minimumSize: WidgetStatePropertyAll(
                Size(
                  0,
                  widget.compact
                      ? WindowChrome.compactHeight
                      : WindowChrome.height,
                ),
              ),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            child: chip,
          );

    // The actionable chips use a native button so Refresh, Inspector and the
    // platform caption controls are present in the macOS AX tree. The lens is
    // intentionally still a readout, not a fake action.
    return Tooltip(
      message: widget.tooltip ?? semanticLabel,
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: widget.onPressed == null,
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: control,
      ),
    );
  }
}

/// Window buttons, where the OS puts them, in the OS's own geometry.
///
/// Drawn by us only where the platform has no opinion about who draws them:
/// macOS keeps AppKit's traffic lights over our strip, because a lookalike is
/// wrong on hover, wrong under Reduce Transparency, and wrong the day the
/// system changes them.
class _CaptionButtons extends StatelessWidget {
  const _CaptionButtons();

  @override
  Widget build(BuildContext context) {
    final gnome = DesktopWindow.style == WindowChromeStyle.gnome;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: Icons.remove_rounded,
          label: 'Minimise',
          gnome: gnome,
          onPressed: windowManager.minimize,
        ),
        SizedBox(width: gnome ? AppSpacing.sm : 0),
        _CaptionButton(
          icon: Icons.crop_square_rounded,
          label: 'Maximise',
          gnome: gnome,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        SizedBox(width: gnome ? AppSpacing.sm : 0),
        _CaptionButton(
          icon: Icons.close_rounded,
          label: 'Close',
          gnome: gnome,
          danger: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.label,
    required this.gnome,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// GNOME draws 26pt round buttons; Windows draws 44x44 rectangles, and its
  /// maximise button must keep its own hover — snap layouts open from it.
  final bool gnome;
  final bool danger;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = widget.gnome ? 26.0 : 44.0;
    final hoverColor = widget.danger
        ? AppColors.error.withValues(alpha: widget.gnome ? 0.24 : 1.0)
        : colorScheme.onSurface.withValues(alpha: 0.08);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        enabled: true,
        label: widget.label,
        child: IconButton(
          tooltip: widget.label,
          onPressed: widget.onPressed,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: size,
            height: widget.gnome ? size : WindowChrome.height,
          ),
          style: ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.gnome ? size : 0),
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(
              _hovered
                  ? hoverColor
                  : (widget.gnome
                        ? colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          )
                        : Colors.transparent),
            ),
          ),
          icon: Icon(
            widget.icon,
            size: widget.gnome ? 13 : 15,
            color: _hovered && widget.danger && !widget.gnome
                ? colorScheme.onError
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

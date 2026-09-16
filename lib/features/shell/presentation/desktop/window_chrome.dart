import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'package:cupola/core/app_breakpoints.dart';
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
    final compact = AppBreakpoints.isCompactDesktop(context);
    final location = GoRouterState.of(context).uri.path;
    final crumbs = ShellBreadcrumb.of(location);
    final lens = _lensFor(ref, location);

    return DecoratedBox(
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
                    accent: lens.service.accent,
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
                  accent: inspectorOpen ? AppColors.navActivity : null,
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

/// The window's two obligations, for a screen the shell does not host.
///
/// Onboarding gates the shell, and a handful of flows live above it on the root
/// navigator. On macOS those screens are still fine — AppKit lets a frameless
/// window be dragged by its background — but on Windows and Linux a frameless
/// window with no drag region and no caption buttons is a window that cannot be
/// moved and, worse, cannot be closed. So those two platforms get a 44pt strip
/// with exactly what the OS took away, and nothing else: no breadcrumb, no
/// chips, no state. Renders nothing at all on a phone or a Mac.
class WindowDragStrip extends StatelessWidget {
  const WindowDragStrip({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.isSupported || !DesktopWindow.drawsOwnButtons) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: WindowChrome.height,
      child: DragToMoveArea(
        child: Row(
          children: [
            const Spacer(),
            const _CaptionButtons(),
            const SizedBox(width: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// The trail, and therefore the window title.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs});

  final List<Crumb> crumbs;

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
          Icon(
            Icons.chevron_right_rounded,
            size: 13,
            color: CupolaThemeColors.of(context).dimText,
          ),
        );
      }
      final text = Text(
        crumb.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
          color: isLast
              ? colorScheme.onSurface
              : CupolaThemeColors.of(context).dimText,
        ),
      );
      children.add(
        crumb.location == null || isLast
            ? text
            : _CrumbLink(location: crumb.location!, child: text),
      );
    }
    return Semantics(
      // The trail spoken as one sentence: three separate labels with chevrons
      // between them is four announcements for one place.
      label: crumbs.map((c) => c.label).join(', '),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: child,
            ),
        ],
      ),
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

/// A 28pt pill in the strip: label, optional shortcut, optional accent.
///
/// Accented means *on* — the inspector chip is the only one that has a state —
/// and the accent is always the owning surface's colour rather than a status
/// tone, per the Closed Tone Rule.
class _ChromeChip extends StatefulWidget {
  const _ChromeChip({
    required this.label,
    this.compact = false,
    this.shortcut,
    this.icon,
    this.accent,
    this.onPressed,
    this.tooltip,
  });

  final String label;

  /// In a compact window the label goes and the glyph plus the shortcut stay.
  final bool compact;
  final String? shortcut;
  final IconData? icon;
  final Color? accent;
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
    final accent = widget.accent;
    final labelled = !widget.compact || widget.icon == null;
    final chip = Container(
      height: widget.compact ? 26 : 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: accent != null
            ? accent.withValues(alpha: 0.14)
            : (_hovered ? colorScheme.onSurface.withValues(alpha: 0.06) : null),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: accent != null
              ? accent.withValues(alpha: 0.4)
              : colorScheme.outline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 14,
              color: accent != null
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          if (labelled)
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent != null
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.shortcut != null) ...[
            SizedBox(width: labelled ? 6 : 4),
            Text(
              widget.shortcut!,
              style: TextStyle(
                fontSize: 11,
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
    return Tooltip(
      message: widget.tooltip ?? semanticLabel,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: widget.onPressed != null,
          label: semanticLabel,
          excludeSemantics: true,
          child: GestureDetector(onTap: widget.onPressed, child: chip),
        ),
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
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: size,
            height: widget.gnome ? size : WindowChrome.height,
            decoration: BoxDecoration(
              color: _hovered
                  ? hoverColor
                  : (widget.gnome
                        ? colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          )
                        : null),
              shape: widget.gnome ? BoxShape.circle : BoxShape.rectangle,
            ),
            child: Icon(
              widget.icon,
              size: widget.gnome ? 13 : 15,
              color: _hovered && widget.danger && !widget.gnome
                  ? colorScheme.onError
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

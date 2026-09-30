import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/shell_freshness.dart';

/// The deck: where you are, how the stack is, and the way to anything.
///
/// The one part of the desktop shell with no counterpart on the phone — and the
/// reason the window does not read as the phone app stretched wide. It carries
/// one health summary, not the seventeen services: a strip of seventeen glyphs
/// in the highest-contrast band of the window said nothing a glance could use,
/// and buried the one chip that says which room you are in. The services are
/// one keystroke away on ⌘K, which lists every connection by name.
///
/// The same row at every width: a narrower window shows fewer items, never
/// the same items shrunk.
class ServiceDeck extends ConsumerWidget {
  const ServiceDeck({
    super.key,
    required this.compact,
    required this.onCommandDeck,
  });

  final bool compact;
  final VoidCallback onCommandDeck;

  static const double fullHeight = 52;
  static const double compactHeight = 40;

  static double heightFor({required bool compact}) =>
      compact ? compactHeight : fullHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.path;
    final current = _serviceOf(location);
    // The deck names the room only when the page does not. On a service's tab
    // root the tab row is the header and already carries glyph, name and lens
    // (ServiceTabBar.header); a pushed page has no tab row, so it keeps the
    // chip, and so do the canonical tabs.
    final namedByPage =
        current != null &&
        !ServiceHomeScreen.drawsBand(context, current) &&
        isServiceTabRoot(current, location);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Service deck',
      child: Container(
        height: heightFor(compact: compact),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The 390pt desktop specimen still carries the desktop shell after
            // the 56pt rail is taken out. Keep the deck's health signal and its
            // command entry point, but let the latter use its icon/key form so
            // the compact row remains a row instead of overflowing horizontally.
            final narrow = constraints.maxWidth < 500;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? AppSpacing.md : AppSpacing.lg,
              ),
              child: Row(
                children: [
                  if (!namedByPage) ...[
                    _ActiveChip(service: current, compact: compact),
                    SizedBox(width: compact ? AppSpacing.sm : AppSpacing.lg),
                  ],
                  _HealthReadout(narrow: narrow, compact: compact),
                  const Spacer(),
                  if (!narrow) ...[
                    SizedBox(width: compact ? AppSpacing.sm : AppSpacing.lg),
                    const ShellFreshness(),
                  ],
                  SizedBox(width: compact ? AppSpacing.sm : AppSpacing.lg),
                  _JumpPill(
                    compact: compact,
                    narrow: narrow,
                    onPressed: onCommandDeck,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The service the window is currently inside, or null on a canonical tab.
  static ServiceKey? _serviceOf(String location) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.length < 2) return null;
    for (final service in ServiceKey.values) {
      if (service.routeParam == segments[1]) return service;
    }
    return null;
  }
}

/// Where you are: the service and, only if it has a name, the connection.
class _ActiveChip extends ConsumerWidget {
  const _ActiveChip({required this.service, required this.compact});

  final ServiceKey? service;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = this.service;
    final accent = service?.accent ?? colorScheme.primary;
    final instance = service == null
        ? null
        : ref.watch(activeInstanceProvider(service));
    final label = instance?.label.trim() ?? '';

    final chip = Container(
      height: compact ? 26 : 32,
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: compact ? AppSpacing.sm + 3 : AppSpacing.md - 1,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            service?.icon ?? Icons.grid_view_rounded,
            size: 16,
            color: ServiceTheme.onTint(
              accent,
              surface: colorScheme.surface,
              tintAlpha: 0.13,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (compact)
            Flexible(
              child: Text(
                service?.title ?? 'All services',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.chrome(
                  context,
                  size: 12,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            )
          else ...[
            Text(
              service?.title ?? 'All services',
              style: AppTheme.chrome(
                context,
                size: 13,
                weight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                label,
                style: AppTheme.chrome(
                  context,
                  size: 11,
                  color: ServiceTheme.onTint(
                    accent,
                    surface: colorScheme.surface,
                    tintAlpha: 0.13,
                  ),
                ).mono.tabular,
              ),
            ],
          ],
        ],
      ),
    );

    return Semantics(
      label: service == null
          ? 'All services'
          : 'Viewing ${service.title}${label.isEmpty ? '' : ', $label'}',
      excludeSemantics: true,
      child: compact
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: chip,
            )
          : chip,
    );
  }
}

/// The stack in one figure: how many of the configured connections answer.
class _HealthReadout extends ConsumerWidget {
  const _HealthReadout({required this.narrow, required this.compact});

  final bool narrow;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final health = ref.watch(stackHealthProvider);
    return Semantics(
      label: health.sentence,
      excludeSemantics: true,
      child: Container(
        height: compact ? 26 : 30,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: statusToneColor(colorScheme, StatusTone.success)),
            // Checking is not a fault — the deck's aggregate pill has to agree
            // with the pip on the cards, or the same probe reads two ways in
            // one window.
            if (health.checking > 0) _Dot(color: colorScheme.onSurfaceVariant),
            if (health.unreachable > 0)
              _Dot(color: statusToneColor(colorScheme, StatusTone.error)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${health.answering}',
              style: AppTheme.chrome(
                context,
                size: 12,
                color: colorScheme.onSurface,
              ).mono.tabular,
            ),
            const SizedBox(width: 3),
            Text(
              '/ ${health.configured}',
              style: AppTheme.chrome(
                context,
                size: 11,
                weight: FontWeight.w500,
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
            if (health.unreachable > 0 && !narrow) ...[
              const SizedBox(width: 5),
              Text(
                '· ${health.unreachable} down',
                style: AppTheme.chrome(
                  context,
                  size: 11,
                  weight: FontWeight.w500,
                  // Walked against the readout's own container: raw red on
                  // it measured 3.4:1 in light theme.
                  color: statusToneColor(
                    colorScheme,
                    StatusTone.error,
                    surface: colorScheme.surfaceContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    margin: const EdgeInsets.only(right: 3),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The way to anything. A field in shape only — it opens the deck panel.
///
/// Drawn as a field rather than as a button because that is what it does: the
/// panel it opens is a search, and a control shaped like its own result is how
/// a command palette teaches itself.
class _JumpPill extends StatefulWidget {
  const _JumpPill({
    required this.compact,
    required this.narrow,
    required this.onPressed,
  });

  final bool compact;
  final bool narrow;
  final VoidCallback onPressed;

  @override
  State<_JumpPill> createState() => _JumpPillState();
}

class _JumpPillState extends State<_JumpPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      container: true,
      enabled: true,
      label: 'Jump to anything, ${ShellShortcuts.commandDeck}',
      hint: 'Open the command deck',
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Jump to anything  ${ShellShortcuts.commandDeck}',
          waitDuration: const Duration(milliseconds: 500),
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: TextButton(
              onPressed: widget.onPressed,
              style: ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                minimumSize: WidgetStatePropertyAll(
                  Size(44, widget.compact ? 40 : 44),
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
              child: Container(
                height: widget.compact ? 26 : 30,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? AppSpacing.sm : AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: _hovered ? 0.8 : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 14,
                      color: CupolaThemeColors.of(context).dimText,
                    ),
                    if (!widget.narrow) ...[
                      const SizedBox(width: 9),
                      Text(
                        widget.compact ? 'Jump' : 'Jump to anything',
                        style: AppTheme.chrome(
                          context,
                          size: 11,
                          weight: FontWeight.w500,
                          color: CupolaThemeColors.of(context).dimText,
                        ),
                      ),
                      const SizedBox(width: 9),
                    ] else
                      const SizedBox(width: 6),
                    Text(
                      ShellShortcuts.commandDeck,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        color: CupolaThemeColors.of(context).dimText,
                      ).mono.tabular,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/command_deck_entry.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

/// The deck, open: one field, everything behind it.
///
/// Descends *from* the deck strip rather than appearing over the middle of the
/// window, so it reads as the same object expanding — which is the desktop
/// counterpart of the phone's Portal, where the screen recedes into a card and
/// the floor rises beneath it. Same idea, different room: a pointer does not
/// need the gesture, so the panel keeps the gesture's *meaning* (the switcher
/// belongs to the strip you invoked it from) and drops its mechanics.
///
/// Deliberately no backdrop blur. It sits over a list that scrolls and a queue
/// that updates every second, and a blur would repaint the whole window behind
/// it on every frame for an effect nobody is looking at.
class CommandDeck extends ConsumerStatefulWidget {
  const CommandDeck({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<CommandDeck> createState() => _CommandDeckState();
}

class _CommandDeckState extends ConsumerState<CommandDeck> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'command deck');
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<CommandDeckEntry> _results() {
    final query = _controller.text.trim().toLowerCase();
    final all = ref.read(commandDeckEntriesProvider);
    if (query.isEmpty) {
      return all
          .where(
            (e) => e.kind != CommandDeckKind.screen || e.detail == 'Section',
          )
          .toList(growable: false);
    }
    return all.where((e) => e.haystack.contains(query)).toList(growable: false);
  }

  void _move(int delta, int length) {
    if (length == 0) return;
    setState(() => _selected = (_selected + delta) % length);
  }

  /// Enter: go there. Alt-Enter: send it to the inspector instead.
  ///
  /// The second one is the whole reason the panel bothers with a keyboard map —
  /// looking something up without losing the page you were on is what a second
  /// column is *for*.
  void _open(CommandDeckEntry entry, {bool inInspector = false}) {
    final instanceId = entry.instanceId;
    final service = entry.service;
    if (instanceId != null && service != null) {
      // Moving the lens is half of opening a connection; the route is the other
      // half, and it is byte-identical for two connections of one service.
      ref.read(activeInstancesProvider.notifier).select(service, instanceId);
    }
    if (inInspector) {
      ref.read(inspectorStateProvider.notifier).setOpen(true);
    } else {
      GoRouter.of(context).go(entry.location);
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _results();
    final selected = results.isEmpty
        ? null
        : results[_selected.clamp(0, results.length - 1)];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, results.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, results.length),
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (selected != null) _open(selected);
        },
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): () {
          if (selected != null) _open(selected, inInspector: true);
        },
      },
      child: Focus(
        autofocus: true,
        // Both columns stretch: the panel hangs off the field and keeps its
        // width whatever it holds, and the footer (and its hairline) spans the
        // panel. Centred, the footer drew as a strip narrower than the panel
        // and an empty result shrank the whole panel to the footer's width.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeckField(
              controller: _controller,
              focus: _focus,
              onChanged: () => setState(() => _selected = 0),
              onEscape: widget.onClose,
            ),
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.lg - 1),
                  ),
                  border: Border.all(color: colorScheme.outlineVariant),
                  boxShadow: AppElevation.level3(colorScheme),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: results.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: Text(
                                'Nothing by that name.',
                                textAlign: TextAlign.center,
                                style: AppTheme.chrome(
                                  context,
                                  size: 12,
                                  color: CupolaThemeColors.of(context).dimText,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: results.length,
                              itemBuilder: (context, index) => _EntryRow(
                                entry: results[index],
                                selected: index == _selected,
                                onTap: () => _open(results[index]),
                                onHover: () =>
                                    setState(() => _selected = index),
                              ),
                            ),
                    ),
                    const _DeckFooter(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field, which replaces the deck's pill in place.
class _DeckField extends StatelessWidget {
  const _DeckField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onEscape,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;
  final VoidCallback onEscape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.primary, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: colorScheme.onSurface),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              onChanged: (_) => onChanged(),
              style: AppTheme.chrome(
                context,
                size: 13,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Jump to a service, a title, a screen',
                hintStyle: AppTheme.chrome(
                  context,
                  size: 13,
                  color: CupolaThemeColors.of(context).dimText,
                ),
              ),
            ),
          ),
          Text(
            'esc to close',
            style: AppTheme.chrome(
              context,
              size: 11,
              weight: FontWeight.w500,
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final CommandDeckEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = entry.service?.accent ?? colorScheme.primary;
    // The connection glyph is measured against the selected row's wash over
    // the palette, the darker of its two grounds in light theme and the
    // lighter in dark, so it holds AA whether or not the row is selected and
    // does not shift as the selection moves.
    final glyphGround = Color.alphaBlend(
      colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      colorScheme.surfaceContainer,
    );
    final spokenLabel = entry.detail == null
        ? entry.label
        : '${entry.label}, ${entry.detail}';
    return Semantics(
      button: true,
      selected: selected,
      label: spokenLabel,
      hint: 'Open ${entry.label}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 38,
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 1,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md - 1,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: selected
                    ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.5),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    entry.icon ??
                        switch (entry.kind) {
                          CommandDeckKind.recent => Icons.history_rounded,
                          CommandDeckKind.screen => Icons.article_outlined,
                          CommandDeckKind.connection => Icons.dns_outlined,
                        },
                    size: 15,
                    color: entry.kind == CommandDeckKind.connection
                        ? ServiceTheme.onTint(
                            accent,
                            surface: glyphGround,
                            tintAlpha: 0,
                          )
                        : CupolaThemeColors.of(context).dimText,
                  ),
                  const SizedBox(width: AppSpacing.md - 1),
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.chrome(
                        context,
                        size: 12,
                        weight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (entry.detail != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      entry.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The keys, printed where they are used. The deck is the app's keyboard lesson.
class _DeckFooter extends ConsumerWidget {
  const _DeckFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final health = ref.watch(stackHealthProvider);
    final hints = [
      '↑↓ move',
      '⏎ open',
      '${ShellShortcuts.openInInspector} open in inspector',
      '${ShellShortcuts.section(0)}–${ShellShortcuts.section(3)} sections',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg + 4,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.lg - 2),
        ),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      // Wrapped rather than scrolled or truncated: these are the keys, and a
      // key that is cut off has not taught anybody anything. In a narrow window
      // the bar grows a second line instead.
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final hint in hints)
            Text(
              hint,
              style: AppTheme.chrome(
                context,
                size: 11,
                color: CupolaThemeColors.of(context).dimText,
              ).mono.tabular,
            ),
          Text(
            health.headline,
            style: AppTheme.chrome(
              context,
              size: 11,
              weight: FontWeight.w500,
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The descent: 200ms, from behind the strip, and never a bounce.
///
/// The panel is a *revealed* object, not an arriving one — it was always
/// attached to the deck — so it slides out of the strip's own edge and fades
/// only enough to hide the first few pixels of travel.
class CommandDeckTransition extends StatelessWidget {
  const CommandDeckTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppAnimation.emphasizedCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.06),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

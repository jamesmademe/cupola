import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

/// A single, premium empty-state widget used across the app.
///
/// Replaces the several bespoke empty states (dashboard sections, services
/// screen, not-configured placeholder) with one consistent visual language:
/// an icon in a soft circle, a title, an optional body and an optional action.
///
/// Three densities:
/// - [AppEmptyState] (full): screen-centred, larger, for whole pages.
/// - [AppEmptyState.compact]: centred but smaller, for carousels/sections.
/// - [AppEmptyState.inline]: one left-aligned line beside a small glyph, for
///   the *expected* absence — a panel whose source simply does not model this
///   data. A ceremonial icon well and a centred headline read as a failure;
///   when nothing went wrong, the note should cost a row, not a screenful.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppEmptyStateDensity density;

  /// Optional accent for the icon (defaults to a neutral variant tone).
  final Color? accentColor;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accentColor,
  }) : density = AppEmptyStateDensity.full;

  const AppEmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accentColor,
  }) : density = AppEmptyStateDensity.compact;

  /// One line beside a glyph. Takes no [action]: an absence nobody can act on
  /// is the only kind that belongs on a single row.
  const AppEmptyState.inline({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accentColor,
  }) : action = null,
       density = AppEmptyStateDensity.inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = accentColor ?? colorScheme.onSurfaceVariant;

    if (density == AppEmptyStateDensity.inline) {
      return _InlineNote(
        icon: icon,
        title: title,
        message: message,
        accent: accent,
      );
    }

    final compact = density == AppEmptyStateDensity.compact;
    final circleSize = compact ? 52.0 : 72.0;
    final iconSize = compact ? 26.0 : 34.0;

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor != null
                ? accent.withValues(alpha: 0.14)
                : colorScheme.surfaceContainerHigh,
          ),
          // The glyph sits on a 14% wash of its own accent, so the composite —
          // not the accent — is what it has to be legible against.
          child: Icon(
            icon,
            size: iconSize,
            color: ServiceTheme.onTint(
              accent,
              surface: colorScheme.surface,
              tintAlpha: accentColor != null ? 0.14 : 0,
            ),
          ),
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        Text(
          title,
          style:
              (compact
                      ? theme.textTheme.titleSmall!
                      : theme.textTheme.titleMedium!)
                  .weight(FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[
          SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
          action!,
        ],
      ],
    );

    // Deliberately not scrollable, and deliberately `mainAxisSize.min`: this is
    // a leaf, and it is the page that knows whether there is a viewport to
    // scroll. At an accessibility reading size a 72pt icon well, a wrapped
    // title, a two-line message and a 40pt button can clear a short phone —
    // a full-page caller must therefore put this inside a scroll view whose
    // `minHeight` is the viewport, which keeps it centred while it fits and lets
    // it grow past that. `ServicesScreen` is the worked example.
    //
    // Owning the viewport here instead was tried and is wrong: a `LayoutBuilder`
    // cannot report intrinsic dimensions, so it breaks every caller that
    // measures them — `SliverFillRemaining` among them.
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xl : 40,
          vertical: compact ? AppSpacing.xl : AppSpacing.xxl,
        ),
        child: column,
      ),
    );
  }
}

/// An [AppEmptyState] that owns the viewport, for a caller that *is* the page.
///
/// [AppEmptyState] is deliberately not scrollable — see the note in its build —
/// and says that a full-page caller must therefore give it a scroll view whose
/// `minHeight` is the viewport. This is that sentence as a widget, because three
/// callers had the sentence and none had the scroll view: an error message long
/// enough to wrap (a failed request quotes the address it failed on) grew the
/// column past a phone and overflowed it, with the words that explain the
/// failure clipped off the bottom.
///
/// Centred while it fits, scrollable once it does not, which is also what keeps
/// it usable at an accessibility reading size.
class AppEmptyStatePage extends StatelessWidget {
  const AppEmptyStatePage({super.key, required this.emptyState});

  final AppEmptyState emptyState;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: emptyState,
      ),
    ),
  );
}

/// How much room an [AppEmptyState] is allowed to take.
enum AppEmptyStateDensity { full, compact, inline }

/// The [AppEmptyState.inline] body: a glyph and the words, left-aligned so the
/// note sits on the same edge as the rows it stands in for.
class _InlineNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Color accent;

  const _InlineNote({
    required this.icon,
    required this.title,
    this.message,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Optically aligned to the first line of text rather than to the
          // block, so a note that wraps to two lines keeps its glyph on the
          // sentence and not floating in the middle of the paragraph.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 16,
              color: ServiceTheme.onTint(
                accent,
                surface: colorScheme.surface,
                tintAlpha: 0,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall
                      ?.weight(FontWeight.w600)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

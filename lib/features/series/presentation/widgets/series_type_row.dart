import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';

/// The Series type cell in the Sonarr detail's Details card, as a control.
///
/// It used to be a `Text`. The artboard drew a chevron beside it, so the page
/// promised an edit it could not perform — the worst of the three states a
/// field can be in, because a fact with no affordance at least tells the truth.
/// Decision 50 resolves it towards the write: Sonarr's `PUT /api/v3/series/{id}`
/// has always accepted `seriesType`, and nothing but a picker was missing.
///
/// Feature-local on purpose. Decision 25 wants in-place editing on every detail
/// page, but that primitive belongs to `MediaDetailView` and does not exist
/// yet; this is the one field whose write was commissioned by name, so it gets
/// the Sonarr-shaped version rather than a half-built shared one that the real
/// primitive would have to unpick.
///
/// **One semantics node, not three.** Label, value and chevron are a single
/// button that announces "Series type, Anime, button" — the row rule the app
/// applies everywhere else. Without the merge a screen reader stopped on the
/// word "Anime" with nothing saying what it was the answer to.
class SeriesTypeRow extends StatelessWidget {
  const SeriesTypeRow({
    super.key,
    required this.rawValue,
    required this.accent,
    required this.onChanged,
    this.isBusy = false,
  });

  /// Exactly what Sonarr said, so an unrecognised value still prints.
  final String rawValue;

  final Color accent;

  /// Invoked with the chosen wire value. Null leaves the row as a plain fact —
  /// which is what a series that is not in this library is.
  final Future<void> Function(SonarrSeriesType type)? onChanged;

  /// A write is in flight. The row stays readable and stays reachable; it just
  /// refuses a second tap, because two overlapping read-modify-writes against
  /// the same series resource is how one of them loses.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = SonarrSeriesType.fromWire(rawValue);
    // Sonarr's word wins when we do not know it: printing "Unknown" would hide
    // a real value the server is using to parse releases.
    final display = current?.label ?? capitalizeFirst(rawValue);
    final setter = onChanged;

    final valueText = Text(
      display,
      style: theme.textTheme.bodyMedium!
          .weight(FontWeight.w600)
          .copyWith(color: colorScheme.onSurface),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (setter == null) return valueText;

    void open() => _pick(context, current, setter);

    return Semantics(
      container: true,
      // The label, value and chevron collapse into one node — but collapsing
      // them also swallows the `InkWell`'s tap action, which would leave a node
      // that calls itself a button and cannot be activated. `onTap` here is
      // what a screen reader's double-tap actually invokes.
      excludeSemantics: true,
      button: true,
      enabled: !isBusy,
      onTap: isBusy ? null : open,
      label: 'Series type',
      value: display,
      hint: 'Changes how Sonarr numbers this series',
      child: InkWell(
        borderRadius: AppRadius.borderRadiusSm,
        onTap: isBusy ? null : open,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: valueText),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                // Dimmed while a write is in flight, never removed: a chevron
                // that disappears for a second reads as the row losing its
                // affordance.
                color: colorScheme.onSurfaceVariant.withValues(
                  alpha: isBusy ? 0.4 : 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    SonarrSeriesType? current,
    Future<void> Function(SonarrSeriesType type) setter,
  ) async {
    final chosen = await AppBottomSheet.show<SonarrSeriesType>(
      context: context,
      title: 'Series type',
      // The consequence, at the point of choosing. This field is the reason an
      // anime library imports nothing, and the sheet is the only place there is
      // room to say so.
      subtitle: 'How Sonarr reads episode numbers out of a release name',
      icon: Icons.tv_rounded,
      accent: accent,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final type in SonarrSeriesType.values)
            _SeriesTypeOption(
              type: type,
              selected: type == current,
              accent: accent,
              onTap: () => Navigator.of(sheetContext).pop(type),
            ),
        ],
      ),
    );

    if (chosen == null || chosen == current) return;
    await setter(chosen);
  }
}

class _SeriesTypeOption extends StatelessWidget {
  const _SeriesTypeOption({
    required this.type,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final SonarrSeriesType type;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The accent carries the tick and the selected label, so it has to be
    // walked against the sheet's own ground — Sonarr's blue is one of the four
    // fills that clear neither ink at AA on paper.
    final accentInk = ServiceTheme.onTint(
      accent,
      surface: colorScheme.surface,
      tintAlpha: 0,
    );

    void choose() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return Semantics(
      container: true,
      // See the row: excluding the children takes the tap action with them, so
      // the option has to carry its own or the sheet is unusable by voice.
      excludeSemantics: true,
      button: true,
      selected: selected,
      onTap: choose,
      label: type.label,
      // The description is why the option exists; a reader that only hears
      // "Anime" is choosing blind.
      hint: type.description,
      child: InkWell(
        onTap: choose,
        borderRadius: AppRadius.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            // 48dp minimum with the two lines of text; the row is the tap
            // target, not the tick.
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: theme.textTheme.bodyLarge!
                          .weight(selected ? FontWeight.w700 : FontWeight.w500)
                          .copyWith(
                            color: selected ? accentInk : colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 20, color: accentInk),
            ],
          ),
        ),
      ),
    );
  }
}

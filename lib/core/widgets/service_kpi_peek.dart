import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A premium horizontal rail of KPI "stat cards" shown at the top of a service
/// page. Replaces the ad-hoc per-service stat rows with one shared component.
///
/// Feed it an [AsyncValue] of KPIs; it renders a shimmer rail while loading and
/// collapses to nothing on error or when there are no metrics (KPIs are
/// supplementary — they should never show an error state of their own).
class ServiceKpiPeek extends StatelessWidget {
  final AsyncValue<List<ServiceKpi>> kpis;

  /// The service's accent (`ServiceKey.accent`), used for the glyph of a KPI
  /// with no tone of its own. That accent is the lamp for every service, and
  /// through `ServiceTheme.onTint` a glyph asked of the lamp is the room's
  /// primary ink: an untoned KPI is monochrome, and only a tone carries a hue.
  final Color accent;

  final EdgeInsetsGeometry padding;

  const ServiceKpiPeek({
    super.key,
    required this.kpis,
    required this.accent,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  });

  static const double _height = 78;

  @override
  Widget build(BuildContext context) {
    // The card is all text (a value line and a label line), so the rail has to
    // follow the reading size or both get clipped.
    //
    // `textHeight` is the share of [_height] that is text, and it survived the
    // type ramp's new per-role leading untouched: the root
    // `DefaultTextHeightBehavior` keeps a text block's outer edges on the
    // face's natural metrics, so leading only opens the gaps *between* lines and a
    // single line measures exactly what it always did. Both lines here are
    // single lines. Re-derive this only if the card gains wrapping text.
    final railHeight = TextScaleMetrics.boxHeight(
      context,
      base: _height,
      textHeight: 34,
    );
    return kpis.when(
      loading: () => _rail(
        context: context,
        height: railHeight,
        children: List.generate(4, (_) => const _KpiSkeletonCard()),
      ),
      error: (error, _) {
        // A service that was never set up is answered by the page below —
        // `NotConfiguredPlaceholder` — and a rail of em dashes over it would
        // read as a fault to go and fix rather than a service nobody
        // configured. Matched on the string the app throws everywhere for it;
        // see `AsyncValueWidget`.
        if (error.toString().contains('not configured')) {
          return const SizedBox.shrink();
        }
        // Everything else: the figures could not be read, and *that* is the
        // readout. Collapsing to nothing here made "no figures" and "no rail"
        // the same pixels, so a reader had no way to tell a service with
        // nothing to report from one that could not be asked — the same
        // fabrication as a confident zero, told by omission.
        return _rail(
          context: context,
          height: railHeight,
          children: [
            _KpiCard(
              // One card, not four blanks: the rail cannot know which figures
              // this service would have had, and inventing labels for them
              // would be a second fabrication on top of the first.
              //
              // The note is the classified reason, not a guess: "not
              // answering" under a header that had just said Answering was two
              // contradicting facts about one server, when the figures had
              // been refused, not unanswered.
              kpi: ServiceKpi.unavailable(
                label: 'Figures',
                icon: Icons.remove_rounded,
                note: failureLabel(classifyConnectionFailure(error)),
              ),
              fallbackAccent: accent,
            ),
          ],
        );
      },
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _rail(
          context: context,
          height: railHeight,
          children: [
            for (final kpi in items) _KpiCard(kpi: kpi, fallbackAccent: accent),
          ],
        );
      },
    );
  }

  Widget _rail({
    required BuildContext context,
    required List<Widget> children,
    required double height,
  }) {
    return SizedBox(
      height: height,
      // The grown box and the clamped scaler are one mechanism. [boxHeight]
      // stops growing at `TextScaleMetrics.defaultMaxScaleFactor`, so the cards
      // have to *paint* at that same ceiling — otherwise the rail is frozen at
      // 1.6x while the text keeps growing, which measured a real
      // `RenderFlex overflowed by 32 pixels` at a 3.0x reading size on every
      // service dashboard.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => children[index],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final ServiceKpi kpi;
  final Color fallbackAccent;

  const _KpiCard({required this.kpi, required this.fallbackAccent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // A toned KPI paints in its tone; everything else is the primary ink.
    // The tone is resolved against the card's own container, not the scaffold:
    // these cards sit on `surfaceContainer`, and on paper that is the ground
    // the walk has to clear.
    final accent = kpi.isUnavailable
        // A figure that has no value is quieter still: the secondary ink, so an
        // absence never looks like a reading.
        ? colorScheme.onSurfaceVariant
        : kpi.tone == null
        // The accent is the lamp, which `onTint` resolves to the room's ink.
        ? ServiceTheme.onTint(
            fallbackAccent,
            surface: colorScheme.surfaceContainer,
            tintAlpha: 0,
          )
        : statusToneColor(
            colorScheme,
            kpi.tone!,
            surface: colorScheme.surfaceContainer,
          );

    final card = Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: AppElevation.level1(colorScheme),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kpi.icon, size: 14, color: accent),
              const SizedBox(width: AppSpacing.xs),
              // The instrument readout, and the one number on a dashboard that
              // is worth watching change — a library total ticking up after an
              // import, a queue count draining. Safe to roll because the card is
              // `minWidth`, not a fixed width, inside a horizontally scrolling
              // rail: a wider value makes the card wider instead of overflowing,
              // and no ellipsis is being relied on here to save it.
              ReelLine(
                kpi.value,
                options: ReelMotion.figure,
                style: theme.textTheme.titleMedium!.tabular.copyWith(
                  // The em dash demotes to the secondary ink: it is a
                  // placeholder for a figure, not a figure, and full
                  // `onSurface` would give it the weight of one.
                  color: kpi.isUnavailable
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
                  height: 1.1,
                ),
                fallbackMaxLines: 1,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            // The note replaces the label rather than joining it: the rail is
            // two lines tall by construction, and a card that grew a third
            // would overflow every sibling at an accessibility reading size.
            // When the source did not answer, *why* is the more useful of the
            // two — the glyph and the surrounding cards already say which
            // figure this is.
            (kpi.note ?? kpi.label).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    // One node for the card, not three fragments. Left to itself the rail reads
    // as "3", "QUEUE", "—", "CLIENT NOT ANSWERING" — four announcements in
    // reading order that a listener has to reassemble, and an em dash that most
    // screen readers either say as "dash" or skip entirely. See
    // [ServiceKpi.semanticLabel].
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: kpi.semanticLabel,
      child: card,
    );
  }
}

class _KpiSkeletonCard extends StatelessWidget {
  const _KpiSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder.text(width: 44, height: 16),
          const SizedBox(height: 6),
          ShimmerPlaceholder.text(width: 64, height: 9),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// A premium horizontal rail of KPI "stat cards" shown at the top of a service
/// page. Replaces the ad-hoc per-service stat rows with one shared component.
///
/// Feed it an [AsyncValue] of KPIs; it renders a shimmer rail while loading and
/// collapses to nothing on error or when there are no metrics (KPIs are
/// supplementary, so they should never show an error state of their own).
class ServiceKpiPeek extends StatelessWidget {
  final AsyncValue<List<ServiceKpi>> kpis;

  /// Whose figures these are: its accent (`ServiceKey.accent`) is the glyph
  /// of a KPI with no tone of its own, and its word for a refused credential
  /// (`token`, `sign-in`) is the note of a rail it could not read. That accent
  /// is the lamp for every service, and through `ServiceTheme.onTint` a glyph
  /// asked of the lamp is the room's primary ink: an untoned KPI is
  /// monochrome, and only a tone carries a hue.
  final ServiceKey service;

  final EdgeInsetsGeometry padding;

  /// The rail alone: a library's figures over its grid.
  const ServiceKpiPeek({
    super.key,
    required this.kpis,
    required this.service,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  }) : _hero = false;

  /// A service room's readout (its Overview): the figure the room leads with
  /// as its hero, the rest as the rail under it.
  const ServiceKpiPeek.room({
    super.key,
    required this.kpis,
    required this.service,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  }) : _hero = true;

  final bool _hero;

  static const double _height = 94;

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
      textHeight: 41,
    );
    // `skipLoadingOnReload`: a page's poll asks its sources again every few
    // seconds, and each ask reloads this rail. Back to skeleton on every tick
    // made the figures blink, and on a client that stopped answering left the
    // rail blank until the read timed out, under a fault band that already
    // says the page is old. The last figures stay until new ones arrive.
    return kpis.when(
      skipLoadingOnReload: true,
      loading: () => _rail(
        context: context,
        height: railHeight,
        children: List.generate(4, (_) => const _KpiSkeletonCard()),
      ),
      error: (error, _) {
        // A service that was never set up is answered by the page below:
        // `NotConfiguredPlaceholder`, and a rail of em dashes over it would
        // read as a fault to go and fix rather than a service nobody
        // configured. Matched on the type the app throws everywhere for it
        // ([ServiceNotConfigured]), as `AsyncValueWidget` does.
        if (error is ServiceNotConfigured) {
          return const SizedBox.shrink();
        }
        // Everything else: the figures could not be read, and *that* is the
        // readout. Collapsing to nothing here made "no figures" and "no rail"
        // the same pixels, so a reader had no way to tell a service with
        // nothing to report from one that could not be asked, the same
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
                note: failureLabel(
                  classifyConnectionFailure(error),
                  credential: refusedCredentialOf(service),
                  gateway: accessGatewayOf(error),
                ),
              ),
              fallbackAccent: service.accent,
            ),
          ],
        );
      },
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        if (!_hero) {
          return _rail(
            context: context,
            height: railHeight,
            children: [
              for (final kpi in items)
                _KpiCard(kpi: kpi, fallbackAccent: service.accent),
            ],
          );
        }
        // The room's one hero readout (`412 movies`), the rest as tiles
        // under it.
        final lead = _leadOf(items);
        final rest = [
          for (final kpi in items)
            if (!identical(kpi, lead)) kpi,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroFigure(kpi: lead),
            if (rest.isNotEmpty)
              _rail(
                context: context,
                height: railHeight,
                children: [
                  for (final kpi in rest)
                    _KpiCard(kpi: kpi, fallbackAccent: service.accent),
                ],
              ),
          ],
        );
      },
    );
  }

  /// The figure the room leads with: a download client's speed, else the
  /// first figure, which every service lists as what it holds.
  ServiceKpi _leadOf(List<ServiceKpi> items) {
    const byService = {
      ServiceKey.qbittorrent: 'Download',
      ServiceKey.transmission: 'Download',
      ServiceKey.sabnzbd: 'Download',
      ServiceKey.nzbget: 'Download',
    };
    final label = byService[service];
    return items.firstWhere(
      (kpi) => kpi.label == label,
      orElse: () => items.first,
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
      // have to *paint* at that same ceiling, otherwise the rail is frozen at
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

/// [noun], a count's plural label, for a count of one: `streams` reads
/// `stream`, `libraries` `library`. A label that is not a plural (`wanted`,
/// `series`, `status`) is itself.
@visibleForTesting
String heroUnitForOne(String noun) {
  final words = noun.split(' ');
  final last = words.last;
  final lower = last.toLowerCase();
  final one = switch (lower) {
    'series' || 'status' => last,
    'movies' => last.substring(0, last.length - 1),
    _ when lower.endsWith('ies') && lower.length > 4 =>
      '${last.substring(0, last.length - 3)}y',
    _ when lower.endsWith('ss') => last,
    _ when lower.endsWith('s') && lower.length > 2 => last.substring(
      0,
      last.length - 1,
    ),
    _ => last,
  };
  return [...words.sublist(0, words.length - 1), one].join(' ');
}

/// The room's hero readout: the figure in the room's largest face and what it
/// counts beside it, in the secondary ink (`412 movies`).
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.kpi});

  final ServiceKpi kpi;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final label = kpi.note ?? kpi.label;
    // A noun reads as the figure's unit: `4 movies`, never `4 Movies`; a
    // label that is an initialism keeps its case; and one of it is one,
    // `1 stream`.
    final noun = label.length > 1 && label[1] == label[1].toLowerCase()
        ? label[0].toLowerCase() + label.substring(1)
        : label;
    final unit = kpi.value.trim() == '1' ? heroUnitForOne(noun) : noun;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: kpi.semanticLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.sm,
            children: [
              ReelLine(
                kpi.value,
                options: ReelMotion.figure,
                style: AppType.figureHero.copyWith(
                  color: kpi.isUnavailable ? room.inkSecondary : room.ink,
                ),
                fallbackMaxLines: 1,
              ),
              Padding(
                // The unit sits on the figure's baseline, not its foot.
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: AppType.section.copyWith(color: room.inkSecondary),
                ),
              ),
            ],
          ),
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

    final room = CupolaRoom.of(context);
    // The room's tile: a slab, the figure in the room's face and the label
    // under it, the tone a dot beside the label as a legend draws it. The
    // figure is the ink; an em dash is the secondary ink, a placeholder for a
    // figure rather than one.
    final card = Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The instrument readout, and the one number on a dashboard that
          // is worth watching change: a library total ticking up after an
          // import, a queue count draining. Safe to roll because the card is
          // `minWidth`, not a fixed width, inside a horizontally scrolling
          // rail: a wider value makes the card wider instead of overflowing.
          ReelLine(
            kpi.value,
            options: ReelMotion.figure,
            style: AppType.figure.copyWith(
              color: kpi.isUnavailable ? room.inkSecondary : room.ink,
            ),
            fallbackMaxLines: 1,
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kpi.tone != null && !kpi.isUnavailable) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // The note replaces the label rather than joining it: the tile
              // is two lines tall by construction. When the source did not
              // answer, *why* is the more useful of the two.
              Flexible(
                child: Text(
                  kpi.note ?? kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
              ),
            ],
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
    final room = CupolaRoom.of(context);
    return Container(
      width: 104,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder.text(width: 44, height: 22),
          const SizedBox(height: 8),
          ShimmerPlaceholder.text(width: 64, height: 11),
        ],
      ),
    );
  }
}

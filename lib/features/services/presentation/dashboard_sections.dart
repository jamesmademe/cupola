/// The Dashboard's regions below the header: what needs you, what is moving,
/// and what landed.
///
/// Three regions, in that order, and the order is the argument. The page asks
/// three questions — *is everything all right* (the header and the alert band),
/// *what needs me* (decisions), *what is happening* (in flight, then recently
/// added) — and the stack itself sits fourth, because it is a launcher and not
/// the headline.
///
/// The Requests region that used to live here is gone, absorbed rather than
/// deleted: a pending request is one *kind* of thing waiting on a human, and it
/// had a region of its own only because it was the one kind anybody had wired
/// up. A stalled download, a failing indexer, a stopped stack, an expiring
/// certificate and a failed import are the same question asked by five other
/// services, and six regions that are empty most of the time is six headings to
/// scroll past to learn that nothing is wrong. See
/// `domain/dashboard_decision.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Region 3 — everything waiting on a human, from every source, in one list.
///
/// Absent when nothing is waiting, for the same reason the alert band is absent
/// when everything answers: **presence is the signal**. A permanent "nothing
/// needs you" heading is a region that is empty on almost every open, which is a
/// heading nobody reads on the day it fills.
///
/// Absent only then, though. While no source has said anything it is a
/// skeleton, and when every source failed it is one fault line: both used to
/// draw nothing, which told the user nothing needed them about a stack that
/// had not been — or could not be — asked. See [DecisionsRegion].
class DashboardDecisionsSection extends ConsumerWidget {
  const DashboardDecisionsSection({super.key});

  static const _title = 'Needs a decision';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(dashboardDecisionsProvider);
    final decisions = read.decisions;
    final coverage = read.coverage;
    final primary = Theme.of(context).colorScheme.primary;

    // The ~30pt header InkWell the code already has. Raising it is a new rule
    // for code and canvas both, and not this region's to make.
    Widget header({String? eyebrow, String? note, String? seeAll}) =>
        SectionHeader.action(
          title: _title,
          subtitle: eyebrow,
          trailing: _SectionAction(
            label: seeAll ?? 'Activity',
            color: primary,
            onTap: () => context.go('/activity'),
          ),
          semanticLabel: joinSpokenParts([
            _title,
            if (eyebrow != null) spokenCountPhrase(eyebrow),
            if (note != null) spokenFromDotted(note),
          ]),
        );

    switch (decisionsRegion(decisions, coverage)) {
      case DecisionsRegion.absent:
        return const SizedBox.shrink();
      case DecisionsRegion.loading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              container: true,
              // The shimmer carries no text; this is what is said instead.
              excludeSemantics: true,
              label: 'Loading decisions',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: DecisionRowSkeleton(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      case DecisionsRegion.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(),
            _SourcesFaultLine(
              coverage: coverage,
              onRetry: () =>
                  retryDashboardServices(ref, coverage.failedServices),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      case DecisionsRegion.shown:
        break;
    }

    // Three on the phone, four on the desktop, two when the window is narrow.
    // The rule is `AppBreakpoints`', resolved here and passed pure — see
    // `decisionCapFor`.
    final cap = decisionCapFor(
      desktopShell: AppBreakpoints.isDesktopShell(context),
      compact: AppBreakpoints.isCompactDesktop(context),
    );
    final shown = rankDecisions(decisions, cap: cap);
    final eyebrow = decisionsEyebrow(decisions, floor: coverage.isFloor);
    final note = coverageNote(coverage);
    final items = decisionItemCount(decisions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header(
          eyebrow: eyebrow,
          note: note,
          // Items, not rows: a folded row of eighteen blocked imports is
          // eighteen things to see, and the row count is a layout fact.
          seeAll:
              'See all ${coverage.isFloor ? Lexicon.floor(items) : '$items'}',
        ),
        if (note != null) _CoverageNote(note: note, coverage: coverage),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            children: [
              for (final decision in shown)
                _DecisionRow(key: ValueKey(decision.id), decision: decision),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Region 5 — what is moving right now.
///
/// Active transfers only. A stalled one is not in flight, it is a decision, and
/// it says so in the footnote rather than silently making this count disagree
/// with the client's own queue depth.
class ServicesInFlightSection extends ConsumerWidget {
  const ServicesInFlightSection({super.key});

  /// Any service that can report a transfer, not just the two arrs the old gate
  /// checked.
  static const _sources = [
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.readarr,
    ServiceKey.qbittorrent,
    ServiceKey.transmission,
    ServiceKey.sabnzbd,
    ServiceKey.nzbget,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final sources = _sources
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (sources.isEmpty) return const SizedBox.shrink();

    final inFlight = ref.watch(servicesInFlightProvider);
    final data = inFlight.asData?.value;
    // The count, never the preview's length: the rows are capped and the
    // eyebrow states a total — over the sources that answered, and only them.
    final eyebrow = data == null
        ? null
        : inFlightEyebrow(
            active: data.activeCount,
            rateBytesPerSecond: data.rateBytesPerSecond,
            clients: data.clients,
            coverage: data.coverage,
          );
    final note = data == null ? null : coverageNote(data.coverage);
    int faultsOf(InFlightFault fault) =>
        data?.faults.where((item) => item.fault == fault).length ?? 0;
    final footnote = data == null
        ? null
        : inFlightFaultFootnote(
            stalled: faultsOf(InFlightFault.stalled),
            needsImport: faultsOf(InFlightFault.needsImport),
            failed: faultsOf(InFlightFault.failed),
            // The faults are rows of the same walks the eyebrow counts: a
            // walk cut short makes them floors too.
            coverage: data.coverage,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader.action(
          // "In flight", not "Downloading": the region also carries a usenet
          // job being repaired and a torrent waiting on a slot, and neither is
          // downloading. One name for one thing, settled on the canvas.
          title: 'In flight',
          subtitle: eyebrow,
          trailing: _SectionAction(
            label: 'Activity',
            // Brand primary, not a service accent: the region spans up to eight
            // sources and no one of them owns it.
            color: Theme.of(context).colorScheme.primary,
            onTap: () => context.go('/activity'),
          ),
          semanticLabel: joinSpokenParts([
            'In flight',
            if (eyebrow != null) spokenCountPhrase(spokenFromDotted(eyebrow)),
            if (note != null) spokenFromDotted(note),
          ]),
        ),
        if (note != null) _CoverageNote(note: note, coverage: data!.coverage),
        const SizedBox(height: AppSpacing.sm),
        AsyncValueWidget<ServicesInFlight>(
          value: inFlight,
          serviceName: 'download queue',
          onRetry: () => ref.invalidate(servicesQueueProvider),
          data: (value) {
            if (value.coverage.everySourceFailed) {
              return _SourcesFaultLine(
                coverage: value.coverage,
                onRetry: () =>
                    retryDashboardServices(ref, value.coverage.failedServices),
              );
            }
            if (value.preview.isEmpty) {
              return _SectionEmptyLabel(
                // Not "Nothing downloading", which the header now says. An
                // empty transfer list is a fact about the queue, so name the
                // queue — and only call it empty when it is, rather than over
                // a footnote counting what it holds or a note naming a source
                // that did not answer.
                label: inFlightEmptyLabel(
                  faults: value.faults.length,
                  held: value.held,
                  whole: value.coverage.isWhole,
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: [
                  for (final item in value.preview)
                    _InFlightRow(
                      // With the connection: two Radarr both number their
                      // queues from one.
                      key: ValueKey(
                        '${item.service}-${item.instanceId}-${item.id}',
                      ),
                      item: item,
                    ),
                ],
              ),
            );
          },
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              footnote,
              semanticsLabel: spokenFaultFootnote(footnote),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Region 6 — what the arrs actually imported, newest first.
///
/// One region and one channel: the old "Finished today" band folded into this
/// one, so a failure is *named* here (in amber, in the eyebrow) and *acted on*
/// in the decisions region, rather than sitting in a band of its own where a
/// failure went to die.
class ServicesRecentlyAddedSection extends ConsumerWidget {
  const ServicesRecentlyAddedSection({super.key});

  static const _libraries = [
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final libraries = _libraries
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (libraries.isEmpty) return const SizedBox.shrink();

    final items = ref.watch(servicesRecentlyAddedProvider);
    final read = items.asData?.value;
    final counts = read == null
        ? null
        : recentlyAddedEyebrow(read.items, coverage: read.coverage);
    final note = read == null ? null : coverageNote(read.coverage);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader.action(
          title: 'Recently added',
          trailing: _SectionAction(
            // History, not Search: this rail is a record of what the arrs did,
            // and the place that record continues is Activity's history — a
            // search screen is where you go to look for something you do not
            // have yet.
            label: 'History',
            color: colorScheme.primary,
            onTap: () => context.go('/activity'),
          ),
          semanticLabel: joinSpokenParts([
            'Recently added',
            if (counts != null) spokenCountPhrase(counts.imported),
            if (counts?.failed case final failed?) spokenCountPhrase(failed),
            if (note != null) spokenFromDotted(note),
          ]),
        ),
        if (counts != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _ImportCounts(
              imported: counts.imported,
              failed: counts.failed,
            ),
          ),
        if (note != null) _CoverageNote(note: note, coverage: read!.coverage),
        const SizedBox(height: AppSpacing.sm),
        AsyncValueWidget<ServicesRecentlyAdded>(
          value: items,
          serviceName: 'your libraries',
          onRetry: () => ref.invalidate(servicesArrHistoryProvider),
          skeleton: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppSkeleton.posterRow(height: 90),
          ),
          data: (data) {
            if (data.coverage.everySourceFailed) {
              return _SourcesFaultLine(
                coverage: data.coverage,
                onRetry: () =>
                    retryDashboardServices(ref, data.coverage.failedServices),
              );
            }
            if (data.items.isEmpty) {
              return const _SectionEmptyLabel(
                // Not "No items found", which is search vocabulary and implies
                // a query this rail never ran.
                label: 'Nothing imported yet',
              );
            }
            // The phone gets the rail; anything with room gets rows, which can
            // carry the title, the time and the service without truncating any
            // of the three. The reduction rule is Reflow's — fewer items, never
            // smaller ones — and a row is not a smaller tile.
            // The eyebrow counted every row; the rail draws the newest few.
            final shown = data.items
                .take(servicesRecentlyAddedLimit)
                .toList(growable: false);
            return AppBreakpoints.isDesktopShell(context)
                ? _RecentlyAddedRows(items: shown)
                : _RecentlyAddedRail(items: shown);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// `5 imported · 1 failed`, with only the second half coloured.
///
/// A failed import is a **fault**, and faults are amber. The red the old band
/// used is reserved for a connection that did not answer — a file the arr could
/// not move is not a server that is gone.
class _ImportCounts extends StatelessWidget {
  const _ImportCounts({required this.imported, required this.failed});

  final String imported;
  final String? failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall;

    return ExcludeSemantics(
      child: Row(
        children: [
          Text(
            imported,
            style: style?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (failed != null) ...[
            Text(
              ' · ',
              style: style?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            Text(
              failed!,
              style: style
                  ?.weight(FontWeight.w600)
                  .copyWith(
                    color: statusToneColor(
                      colorScheme,
                      StatusTone.warning,
                      surface: colorScheme.surface,
                    ),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The phone's rail: six 60×90 tiles with the title on the tile, clipped by a
/// right-edge fade.
///
/// The fade is the affordance. A rail that simply ends at the screen edge looks
/// like a list that fits; one whose last tile dissolves says there is more to
/// the right without spending a row on a chevron.
class _RecentlyAddedRail extends StatelessWidget {
  const _RecentlyAddedRail({required this.items});

  final List<RecentlyAddedItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TextScaleMetrics.boxHeight(context, base: 90, textHeight: 26),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // Opaque until the last tenth, then out. Any softer and the fade
          // reads as a rendering fault on the tile rather than as an edge.
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.9, 1],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.carouselGap),
            itemBuilder: (context, index) => _RecentTile(item: items[index]),
          ),
        ),
      ),
    );
  }
}

/// One 60×90 tile: the poster, the title over a scrim, and — when it failed —
/// an amber marker.
class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item});

  final RecentlyAddedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final time = formatImportedAt(item.addedAt);

    return SizedBox(
      width: 60,
      child: PressableScale(
        onTap: () => _openRecentlyAdded(context, item),
        // Every tile is a tap target, and its accessible name carries the three
        // facts a 60×90 box can only show two of.
        semanticLabel: recentlyAddedTileLabel(item, timeLabel: time),
        excludeChildSemantics: true,
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusSm,
          child: SizedBox(
            width: 60,
            height: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HeroContentCard(
                  heroTag: item.heroTag,
                  imageUrl: item.posterUrl,
                ),
                // The title sits ON the tile — there is no room for a caption
                // under six tiles in one rail's height — so it needs a ground of
                // its own to stay legible over any poster.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    alignment: Alignment.bottomLeft,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                      ),
                    ),
                    // The connection under the title once the service has
                    // two: the HD and the 4K copy of one movie are otherwise
                    // two identical tiles. The title gives up its second
                    // line for it, so the scrim keeps its height and a tile
                    // without one draws exactly as before.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: item.connectionName == null ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.weight(FontWeight.w600)
                              .copyWith(color: Colors.white),
                        ),
                        if (item.connectionName != null)
                          Text(
                            // Only what tells the connections apart: the
                            // tile already carries the service's mark. The
                            // long form, `Radarr 4K`, does not fit 60 pt and
                            // its ellipsis cut off exactly that part. A
                            // connection nobody named keeps its place,
                            // `Radarr 1`, which is the one the rule gives it.
                            item.connectionName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (item.failed)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _FailedChip(
                      // Amber, through the token rather than through the raw
                      // palette: a failed import is a fault, and the red the old
                      // band used is reserved for a connection that did not
                      // answer.
                      tone: statusToneColor(colorScheme, StatusTone.warning),
                    ),
                  ),
                if (item.posterUrl.isEmpty)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        item.service.icon,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
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

/// The marker on a tile whose import failed.
///
/// A solid chip rather than the 14% wash the in-page pills use: it sits on an
/// arbitrary poster, and a wash over an unknown image is not a contrast anybody
/// can promise. The ink is walked against the fill it actually lands on.
class _FailedChip extends StatelessWidget {
  const _FailedChip({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        'failed',
        style: Theme.of(context).textTheme.labelSmall
            ?.weight(FontWeight.w600)
            .copyWith(color: ServiceTheme.foregroundOn(tone)),
      ),
    );
  }
}

/// The desktop's rows: title, time, service — it has room for all three.
class _RecentlyAddedRows extends StatelessWidget {
  const _RecentlyAddedRows({required this.items});

  final List<RecentlyAddedItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          for (final item in items)
            _CompactListRow(
              icon: item.service.icon,
              title: item.title,
              subtitle: joinDisplayParts([
                item.failed
                    ? 'failed import'
                    : serviceWithConnection(
                        item.service,
                        item.connectionName,
                        joiner: ' ',
                      ),
                item.subtitle,
                formatImportedAt(item.addedAt),
              ]),
              imageUrl: item.posterUrl.isEmpty ? null : item.posterUrl,
              heroTag: item.heroTag,
              trailing: const SizedBox.shrink(),
              semanticValue: recentlyAddedTileLabel(
                item,
                timeLabel: formatImportedAt(item.addedAt),
              ),
              onTap: () => _openRecentlyAdded(context, item),
            ),
        ],
      ),
    );
  }
}

void _openRecentlyAdded(BuildContext context, RecentlyAddedItem item) {
  if (item.id <= 0) {
    // A history record that names no library item — a failed grab of something
    // the arr never added. The service's own page is the honest destination; a
    // detail route for id 0 is a dead end.
    context.go(ServiceRoutes.forService(item.service));
    return;
  }
  // With the connection the record came off: its id is that server's.
  final route = switch (item.service) {
    ServiceKey.radarr => ServiceRoutes.radarrMovie(
      item.id,
      heroTag: item.heroTag,
      instanceId: item.instanceId,
    ),
    ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
      item.id,
      heroTag: item.heroTag,
      instanceId: item.instanceId,
    ),
    ServiceKey.lidarr => ServiceRoutes.lidarrArtist(
      item.id,
      heroTag: item.heroTag,
      instanceId: item.instanceId,
    ),
    // Unreachable: the provider only emits these three. Falling back to the
    // service hub rather than throwing keeps a future fourth source from
    // crashing a tap before its route exists.
    _ => ServiceRoutes.forService(item.service),
  };
  context.push(route);
}

/// One thing waiting on a human.
///
/// The row body links to the item; the trailing control is the decision. They
/// are never the same destination — a row where "open it" and "do it" are one
/// gesture is a row you cannot inspect before acting.
class _DecisionRow extends ConsumerWidget {
  const _DecisionRow({super.key, required this.decision});

  final DashboardDecision decision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Faults are amber; a pending request is backlog and stays neutral. The tone
    // decides the marker's colour and nothing else — the row is not filled or
    // bordered in it, because six amber rows would be a wall.
    final tone = decision.isFault ? StatusTone.warning : StatusTone.neutral;
    final toneColor = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surfaceContainer,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        key: ValueKey('decision-${decision.id}'),
        onTap: () {
          final route = decision.route;
          if (route == null) return;
          context.push(route);
        },
        semanticLabel: decision.title,
        semanticValue: decisionRowSpokenValue(
          serviceTitle: decision.service.title,
          detail: decision.detail,
          actionLabel: decisionActionLabel(
            decision.kind,
            target: decision.actionTarget,
            renewable: decision.renewable,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            // Everything the row's own label already speaks.
            Expanded(
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      height: 54,
                      child: decision.posterUrl.isEmpty
                          ? _GlyphPlate(
                              icon: decision.service.icon,
                              tone: toneColor,
                            )
                          : _HeroContentCard(
                              heroTag: null,
                              imageUrl: decision.posterUrl,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            decision.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.weight(
                              FontWeight.w600,
                            ),
                          ),
                          Text(
                            decision.detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: decision.isFault
                                  ? toneColor
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Not excluded: these are the point of the row.
            _DecisionControls(decision: decision),
          ],
        ),
      ),
    );
  }
}

/// The trailing control, or the two of them a request needs.
class _DecisionControls extends ConsumerWidget {
  const _DecisionControls({required this.decision});

  final DashboardDecision decision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (decision.kind == DecisionKind.pendingRequest) {
      final id = decision.actionId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RequestDecisionButton.approve(
            title: decision.title,
            onPressed: id == null
                ? null
                : () => ActivityActions.approveRequest(
                    context,
                    ref,
                    // The Seerr the request came off: the region reads every
                    // one, and a request id is per server.
                    instanceId: decision.instanceId,
                    requestId: id,
                    title: decision.title,
                  ),
          ),
          _RequestDecisionButton.decline(
            title: decision.title,
            onPressed: id == null
                ? null
                : () => ActivityActions.declineRequest(
                    context,
                    ref,
                    instanceId: decision.instanceId,
                    requestId: id,
                    title: decision.title,
                  ),
          ),
        ],
      );
    }

    final required = decision.requiresService;
    final label = decisionActionLabel(
      decision.kind,
      target: decision.actionTarget,
      renewable: decision.renewable,
    );

    // Renewing is a write on the certificates of one NPM account, and a
    // view-only account cannot make it: the same gate the Certificates tab
    // draws its own Renew through, so Home never offers what the page beyond
    // it would dim. Dimmed rather than hidden, like every write a credential
    // may not make: the certificate still needs somebody, and the toast says
    // which account can do it. An uploaded certificate has no Renew to gate:
    // its control only opens the certificates, which any account may read.
    if (decision.kind == DecisionKind.expiringCertificate &&
        decision.renewable) {
      return CapabilityGatedAction.builder(
        service: ServiceKey.nginxProxyManager,
        // Empty means the lens, which is the connection the certificates
        // were read through.
        connectionId: decision.instanceId.isNotEmpty
            ? decision.instanceId
            : capabilityConnectionId(ref, ServiceKey.nginxProxyManager),
        resource: NpmResource.certificates.key,
        hint: npmCapabilityHint,
        blockedMessage: npmBlockedMessage(NpmResource.certificates),
        onTap: () => _runDecision(context, ref, decision),
        builder: (context, onPressed, annotate) => _DecisionActionButton(
          label: label,
          onPressed: onPressed,
          annotate: annotate,
        ),
      );
    }

    if (required == null) {
      return _DecisionActionButton(
        label: label,
        onPressed: () => _runDecision(context, ref, decision),
      );
    }

    // Dimmed but tappable, never `Semantics(enabled: false)`: the shared
    // cross-service cell. Hiding or disabling the control would hide the fact
    // with it, and the fact — that this stall can only be touched in a client
    // this stack has no connection to — is what the page is for. Its toast's
    // one action opens that client's settings.
    return CrossServiceAction.builder(
      target: required,
      blockedMessage: decisionUnavailableToast(decision.kind, required),
      onTap: () => _runDecision(context, ref, decision),
      builder: (context, onPressed, annotate) => _DecisionActionButton(
        label: label,
        onPressed: onPressed,
        annotate: annotate,
      ),
    );
  }
}

/// What the trailing control does, per kind.
///
/// Two of the six are real writes from here — approve and decline are handled by
/// [_DecisionControls] above, and Start and Test are below — because both are a
/// single confirmed call this app already owns. The other three *navigate to
/// where the act happens*: a manual import is a three-station wizard, opening a
/// stalled transfer is by design a jump into its client (decision 30: resume in
/// place needs a downloadId-to-hash bridge no client has), and `Renew` opens
/// the Certificates tab, which owns renewal and its confirmation: the call
/// reaches Let's Encrypt, and a renewal fired from a row on Home is one
/// mis-tap from spending the account's rate limits.
Future<void> _runDecision(
  BuildContext context,
  WidgetRef ref,
  DashboardDecision decision,
) async {
  switch (decision.kind) {
    case DecisionKind.pendingRequest:
      return;
    case DecisionKind.stalledDownload:
      // A service's page reads its lens, so the client this transfer is on
      // is brought under the lens first: with two qBittorrent, "Open in
      // qBittorrent" on the seedbox's stall opened the one at home.
      final target = decision.actionTarget;
      final connection = decision.actionInstanceId;
      if (connection.isNotEmpty &&
          connection != ref.read(activeInstanceProvider(target))?.id &&
          ref.read(currentSettingsProvider).instanceById(connection) != null) {
        await ref
            .read(activeInstancesProvider.notifier)
            .select(target, connection);
      }
      if (!context.mounted) return;
      context.go(ServiceRoutes.forService(target));
    case DecisionKind.importBlocked:
      // Where the wizard does not exist, the control said "Open in …" and
      // goes there. Otherwise: the wizard, bound to the connection the record
      // came off, filed under its library item and seeded with the folder the
      // client wrote to — each only when the decision knows it.
      if (!decision.service.supportsManualImport) {
        context.go(ServiceRoutes.forService(decision.service));
        return;
      }
      context.push(
        manualImportLocation(
          manualImportBrowsePath,
          decision.service,
          targetId: decision.actionId,
          folderPath: manualImportFolderFromOutputPath(decision.importPath),
          instanceId: decision.instanceId,
        ),
      );
    case DecisionKind.failedImport:
      context.push(
        manualImportLocation(
          manualImportBrowsePath,
          decision.service,
          targetId: decision.actionId,
          instanceId: decision.instanceId,
        ),
      );
    case DecisionKind.failingIndexer:
      final id = decision.actionId;
      if (id == null) return;
      final indexer = await ref.read(prowlarrIndexerByIdProvider(id).future);
      if (!context.mounted || indexer == null) return;
      await testIndexerFlow(context, ref, indexer);
    case DecisionKind.stoppedStack:
      await runDockgeStackAction(
        context,
        ref,
        (client) => client.startStack(decision.title),
        '${decision.title} started',
        'Could not start ${decision.title}',
        // The stack source reads the list, so dropping the list is enough.
        invalidate: [dockgeStackListProvider],
      );
    case DecisionKind.expiringCertificate:
      // The Certificates tab, where Renew and its confirmation are, and where
      // an uploaded certificate is listed for replacing: the service's root
      // is its Overview, which offers no writes at all.
      context.go(ServiceRoutes.npmCertificates);
  }
}

/// A 38×54 plate carrying the source's glyph, for a decision with no artwork.
class _GlyphPlate extends StatelessWidget {
  const _GlyphPlate({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Icon(icon, size: 18, color: tone),
    );
  }
}

/// The single trailing control on a decision row.
class _DecisionActionButton extends StatelessWidget {
  const _DecisionActionButton({
    required this.label,
    required this.onPressed,
    this.annotate,
  });

  final String label;
  final VoidCallback onPressed;

  /// The dim and hint of a cross-service gate, applied to the label inside
  /// the button. Null for a decision with no other service to reach.
  final Widget Function(Widget content)? annotate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // Brand indigo, never the fault's amber: the cure must not be painted
        // as alarming as the disease.
        foregroundColor: colorScheme.primary,
        // No `visualDensity: compact` here, unlike the alert band's pair: the
        // density is applied *to* the minimum size, so compact turns a declared
        // 44 into a measured 40 and quietly drops the control under both
        // platforms' floors.
        minimumSize: const Size(56, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      // The hint is annotated from INSIDE the button, not from a `Semantics`
      // wrapped around it. A button is a semantic boundary, so an annotation
      // above it either creates a second node the reader has to step through or
      // is dropped entirely; an annotation on its child merges into the button's
      // own node, which is where "requires qBittorrent" has to be heard.
      child: (annotate ?? (content) => content)(
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.weight(FontWeight.w600),
        ),
      ),
    );
  }
}

/// One of the two inline decisions on a pending request.
///
/// Both are icon-only, so both carry the media title in their name: five pending
/// rows would otherwise offer five identical "Approve" buttons with no way to
/// tell which request each belongs to.
class _RequestDecisionButton extends StatelessWidget {
  const _RequestDecisionButton._({
    required this.icon,
    required this.verb,
    required this.tone,
    required this.title,
    required this.onPressed,
  });

  const _RequestDecisionButton.approve({
    required String title,
    required VoidCallback? onPressed,
  }) : this._(
         icon: Icons.check_rounded,
         verb: 'Approve',
         tone: StatusTone.success,
         title: title,
         onPressed: onPressed,
       );

  const _RequestDecisionButton.decline({
    required String title,
    required VoidCallback? onPressed,
  }) : this._(
         icon: Icons.close_rounded,
         verb: 'Decline',
         tone: StatusTone.error,
         title: title,
         onPressed: onPressed,
       );

  final IconData icon;
  final String verb;
  final StatusTone tone;
  final String title;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      // The tooltip is already this button's accessible name and three test
      // files assert on `find.byTooltip`, so it stays; the explicit label is
      // added rather than traded for it.
      tooltip: '$verb $title',
      color: ServiceTheme.onTint(
        statusToneColor(colorScheme, tone),
        surface: colorScheme.surfaceContainer,
        tintAlpha: 0,
      ),
      // Material's default 48x48 clears both the 44pt iOS and 48dp Android
      // floors; stated so a later density tweak cannot quietly drop under them.
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
    );
  }
}

/// One transfer, in the grammar every client shares.
///
/// `2160p · 14.0 of 15.2 GB · 3 min left · qBittorrent`, in tabular figures
/// so a column of them lines up — see `domain/in_flight.dart` for why the four
/// fields are the four fields.
class _InFlightRow extends StatelessWidget {
  const _InFlightRow({super.key, required this.item});

  final ServiceQueueItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = item.progress == null
        ? null
        : (item.progress! * 100).round();
    // The primary ink, not the source service's colour, for both the figure and
    // the bar. Contrast: SABnzbd's gold measured about 1.9:1 as `labelSmall` on
    // the light card and NZBGet's green about 2.9:1, well under AA. Identity:
    // eight download sources each putting a hue on a percentage said nothing
    // the row's name did not. Walked against the row's card.
    final accent = statusToneColor(
      colorScheme,
      StatusTone.primary,
      surface: colorScheme.surfaceContainer,
    );
    final line = formatInFlightLine(
      // A client's own row is named by its client label already.
      connection:
          item.connectionName == null || item.clientService == item.service
          ? null
          : serviceWithConnection(
              item.service,
              item.connectionName,
              joiner: ' ',
            ),
      quality: item.quality,
      doneBytes: item.doneBytes,
      totalBytes: item.totalBytes,
      etaSeconds: item.etaSeconds,
      client: item.clientLabel,
    );

    return _CompactListRow(
      icon: item.service.icon,
      title: item.title,
      subtitle: line,
      tabularSubtitle: true,
      trailing: percent == null
          // Nothing at all when the client reports no progress. It used to print
          // "DL", an abbreviation that says nothing, in the slot where every
          // other row shows a number — so it read as a value rather than as its
          // absence.
          ? const SizedBox.shrink()
          : Text(
              '$percent%',
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .tabular
                  .copyWith(color: accent),
            ),
      semanticValue: inFlightRowValue(line: line, percent: percent),
      progressValue: item.progress,
      progressColor: item.progress == null ? null : accent,
      onTap: () => context.go('/activity'),
    );
  }
}

class _HeroContentCard extends StatelessWidget {
  final String? heroTag;
  final String imageUrl;

  const _HeroContentCard({required this.heroTag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(imageUrl: imageUrl);
    // Only fly a Hero when there is both a tag AND an image on this end. An
    // empty image would produce a blank/orphaned Hero whose destination has no
    // matching poster, which shows up as a fade instead of a shared-element
    // flight.
    if (heroTag == null || heroTag!.isEmpty || imageUrl.isEmpty) {
      return card;
    }

    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: card,
    );
  }
}

class _CompactListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Whether [subtitle] is a data line rather than prose.
  ///
  /// The in-flight row's fields are figures that update in place, so the line
  /// takes tabular digits (the Tabular Rule). It stays in the text face:
  /// figures are never mono, which is for machine strings only.
  final bool tabularSubtitle;
  final String? imageUrl;
  final String? heroTag;
  final Widget trailing;
  final double? progressValue;
  final Color? progressColor;
  final VoidCallback onTap;

  /// Everything announced after [title].
  ///
  /// Composed by the caller because [trailing] is an opaque widget and only the
  /// caller knows what is in it — the percentage, the status. It also folds in
  /// the progress bar, which publishes nothing of its own and whose "75%" label
  /// lives in a sibling subtree on screen.
  final String semanticValue;

  const _CompactListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.semanticValue,
    required this.onTap,
    this.tabularSubtitle = false,
    this.imageUrl,
    this.heroTag,
    this.progressValue,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        onTap: onTap,
        semanticLabel: title,
        semanticValue: semanticValue,
        // Nothing in this row is interactive on its own. Note the deliberate
        // absence of LinearProgressIndicator.semanticsLabel: it would add a
        // second focus stop *inside* a button, which is worse than the bar being
        // silent.
        excludeChildSemantics: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 54,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: AppRadius.borderRadiusSm,
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : _HeroContentCard(heroTag: heroTag, imageUrl: imageUrl!),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.weight(FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tabularSubtitle
                        ? subtitleStyle?.tabular
                        : subtitleStyle,
                  ),
                  if (progressColor != null) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 3,
                        color: progressColor,
                        backgroundColor: colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusSm,
      child: ConstrainedBox(
        // The ~30pt header control the code already had, kept at that height on
        // purpose: raising it to 44 is a new rule for code and canvas both, and
        // this region is not the place to make it.
        constraints: const BoxConstraints(minHeight: 30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Center(
            child: Text(
              '$label →',
              // One line, always. The arrow belongs to the words before it, so a
              // wrap that stranded it on its own line would read as a second
              // control.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.weight(FontWeight.w600)
                  .copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a dashboard section says when its sources answered and had nothing.
///
/// Only then. A source that did not answer, or answered with a refusal, is not
/// an empty library, and the section says so from the read itself — the line
/// under its figure ([_CoverageNote]) when some sources answered, the fault
/// line ([_SourcesFaultLine]) when none did. Before the read carried that, a
/// browse that degraded to `[]` arrived here exactly like an empty one, and the
/// merged regions printed the empty copy over a missing connection.
class _SectionEmptyLabel extends StatelessWidget {
  const _SectionEmptyLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The line under a total that leaves sources out: `Not in the total:
/// SABnzbd`.
///
/// A [FaultNote] — the tone on one glyph, the sentence in secondary ink — and
/// silent to a screen reader, because the section header already speaks it as
/// part of its one sentence: a figure and the fact that qualifies it are one
/// thing to hear, not two stops.
class _CoverageNote extends StatelessWidget {
  const _CoverageNote({required this.note, required this.coverage});

  final String note;
  final SourceCoverage coverage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      child: ExcludeSemantics(
        child: coverage.anyDidNotAnswer
            ? FaultNote.unreachable(message: note)
            : FaultNote.fault(message: note),
      ),
    );
  }
}

/// A section whose every source failed: one quiet line in its tone, in place
/// of the rows and of any figure.
///
/// Red only when a source did not answer — the band names who and why, and a
/// refused key among them is said in its own words. Amber when every one of
/// them answered with a fault. Never a coloured box: the presence rule keeps
/// the tone on the glyph and the recovery verb in ink.
///
/// Its Retry is `retryDashboardServices` over the failed sources, never the
/// summary or the merge alone: both re-read an answer already in the cache —
/// the probe behind the summary, the client queues behind the merge — so the
/// line used to outlive the recovery it was asking about.
class _SourcesFaultLine extends StatelessWidget {
  const _SourcesFaultLine({required this.coverage, required this.onRetry});

  final SourceCoverage coverage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = coverageFailureSentence(coverage);
    return coverage.anyDidNotAnswer
        ? FaultBand.section(message: message, onRetry: onRetry)
        : FaultBand.partial(message: message, onRetry: onRetry);
  }
}

/// Skeleton placeholder for one decision row while the merge resolves.
class DecisionRowSkeleton extends StatelessWidget {
  const DecisionRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 38,
              height: 54,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder.text(width: 140),
                  const SizedBox(height: AppSpacing.xs),
                  ShimmerPlaceholder.text(width: 90),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShimmerPlaceholder(
              width: 110,
              height: 26,
              borderRadius: AppRadius.borderRadiusSm,
            ),
          ],
        ),
      ),
    );
  }
}

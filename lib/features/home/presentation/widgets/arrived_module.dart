/// Arrived: what the libraries gained in the last seven days.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/rail_arrows.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/arrived_last_known.dart';
import 'package:cupola/features/home/domain/arrived.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show askedAgo;
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Arrived: one card per movie, new series or album imported in the last
/// seven days, the newest first, each opening its page.
///
/// Absent when nothing arrived and every library answered. A library that did
/// not answer keeps the module in its place: what arrived there is not known.
class HomeArrivedModule extends ConsumerWidget {
  const HomeArrivedModule({super.key});

  static const _title = 'Arrived';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final libraries = HomeModule.arrived.services
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (libraries.isEmpty) return const SizedBox.shrink();

    // The live answer, or until it comes the last drawing (a cold start).
    final read = ref.watchOrLastKnown(
      servicesArrivalsProvider,
      arrivedLastKnown,
    );
    final live = read.live;
    final history = read.value;
    if (history == null) {
      if (live.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: _silentOf(libraries, live.error),
          onRetry: () => ref.invalidate(servicesArrivalsProvider),
        );
      }
      return const HomeModuleFrame.loading(
        title: _title,
        skeleton: _ArrivedSkeleton(),
      );
    }

    final coverage = history.coverage;
    void retry() => retryDashboardServices(ref, coverage.failedServices);
    if (coverage.everySourceFailed) {
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: retry,
      );
    }

    // A drawing over a failure: the live read failed, or answered with no
    // library answering; its words are the live read's own.
    final failed = live.hasError || read.silent;
    SourceCoverage failure() =>
        read.silent ? live.value!.coverage : _silentOf(libraries, live.error);
    void retryFailed() => read.silent
        ? retryDashboardServices(ref, live.value!.coverage.failedServices)
        : ref.invalidate(servicesArrivalsProvider);

    final now = ref.watch(arrivalsClockProvider)();
    final cards = arrivedOf(
      history.entries,
      since: ref.watch(arrivalsSinceProvider),
    );
    final known = read.asOf;
    if (cards.isEmpty) {
      // A last drawing whose week has gone by says nothing: loading, as if
      // there were none.
      if (known != null) {
        return failed
            ? HomeModuleFrame.silent(
                title: _title,
                coverage: failure(),
                onRetry: retryFailed,
              )
            : const HomeModuleFrame.loading(
                title: _title,
                skeleton: _ArrivedSkeleton(),
              );
      }
      // Nothing to say only when every library said so.
      if (coverage.failed.isEmpty) return const SizedBox.shrink();
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: retry,
      );
    }

    final subtitle = arrivedSubtitle(cards.length, coverage);
    final note = coverage.failed.isEmpty
        ? null
        : coverageFailureSentence(coverage);
    final rail = _ArrivedRail(
      cards: cards.take(arrivedCardLimit).toList(growable: false),
      now: now,
    );

    // The last drawing whose live read failed: the cards it knew, at full
    // ink, over the failure in its own words.
    if (known != null && failed) {
      return LastKnownMark(
        asOf: known,
        checking: false,
        child: HomeModuleFrame.silent(
          title: _title,
          coverage: failure(),
          onRetry: retryFailed,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: rail,
          ),
        ),
      );
    }

    return LastKnownMark(
      asOf: known,
      checking: true,
      child: RailArrows(
        builder: (context, controller, arrows) => HomeModuleFrame(
          title: _title,
          subtitle: subtitle,
          semanticLabel: joinSpokenParts([
            _title,
            spokenFromDotted(subtitle),
            ?note,
          ]),
          rail: arrows,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null)
                HomeCoverageNote(note: note, coverage: coverage),
              const SizedBox(height: AppSpacing.xs),
              rail.withController(controller),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  /// Every library silent, for the one read that failed whole.
  static SourceCoverage _silentOf(List<ServiceKey> libraries, Object? error) =>
      SourceCoverage.merge([
        for (final service in libraries) SourceCoverage.failure(service, error),
      ]);
}

/// `2 h ago`, `Yesterday`, `Sunday`: when a card arrived, as a line starts.
String arrivedWhen(DateTime at, {required DateTime now}) {
  final words = askedAgo(at, now: now);
  return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// The cards, side by side, the rail running off the edge of the slab.
class _ArrivedRail extends StatelessWidget {
  const _ArrivedRail({required this.cards, required this.now})
    : controller = null;

  const _ArrivedRail._(this.cards, this.now, this.controller);

  final List<ArrHistoryEntry> cards;
  final DateTime now;

  /// The rail's scroll, when its heading carries the arrows.
  final ScrollController? controller;

  _ArrivedRail withController(ScrollController controller) =>
      _ArrivedRail._(cards, now, controller);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TextScaleMetrics.boxHeight(
        context,
        base: ArrivedCard.artHeight + AppSpacing.sm + 40,
        textHeight: 40,
      ),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) =>
              ArrivedCard(entry: cards[index], now: now),
        ),
      ),
    );
  }
}

/// One title that arrived: its wide artwork, its name, and when and where it
/// came.
class ArrivedCard extends StatelessWidget {
  const ArrivedCard({super.key, required this.entry, required this.now});

  final ArrHistoryEntry entry;
  final DateTime now;

  static const double width = 200;
  static const double artHeight = width * 9 / 16;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final at = entry.at!;
    final line = arrivedCardLine(entry, when: arrivedWhen(at, now: now));
    final art = entry.backdropUrl.isNotEmpty
        ? entry.backdropUrl
        : entry.posterUrl;
    return SizedBox(
      width: width,
      child: PressableScale(
        onTap: () => openArrived(context, entry),
        semanticLabel: '${entry.title}, ${spokenFromDotted(line)}',
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: artHeight,
              child: art.isEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: room.fillQuiet,
                        borderRadius: AppRadius.borderRadiusMd,
                      ),
                      child: Icon(
                        entry.service.icon,
                        size: 22,
                        color: room.inkSecondary,
                      ),
                    )
                  : ClipRRect(
                      borderRadius: AppRadius.borderRadiusMd,
                      child: ContentCard(imageUrl: art),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.row
                  .weight(FontWeight.w600)
                  .copyWith(color: room.ink),
            ),
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta.tabular.copyWith(color: room.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two card shapes while the libraries are read.
class _ArrivedSkeleton extends StatelessWidget {
  const _ArrivedSkeleton();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget bar(double width) => Container(
      width: width,
      height: 10,
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: AppRadius.borderRadiusSm,
      ),
    );
    // The rail's shape runs off the slab as the rail does.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.carouselGap),
            SizedBox(
              width: ArrivedCard.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: ArrivedCard.artHeight,
                    decoration: BoxDecoration(
                      color: room.fillQuiet,
                      borderRadius: AppRadius.borderRadiusMd,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  bar(120),
                  const SizedBox(height: AppSpacing.xs),
                  bar(80),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A card's page: a movie's or a series' Media page on the connection it
/// came to, an album's artist on its Lidarr.
void openArrived(BuildContext context, ArrHistoryEntry entry) {
  final tmdbId = entry.tmdbId ?? 0;
  final focus = entry.instanceId.isEmpty ? null : entry.instanceId;
  if (tmdbId > 0 && entry.service == ServiceKey.radarr) {
    context.openMedia(MediaKey.movie(tmdbId), focus: focus);
    return;
  }
  if (tmdbId > 0 && entry.service == ServiceKey.sonarr) {
    context.openMedia(MediaKey.tv(tmdbId), focus: focus);
    return;
  }
  if (entry.mediaId <= 0) {
    context.go(ServiceRoutes.forService(entry.service));
    return;
  }
  context.push(switch (entry.service) {
    ServiceKey.radarr => ServiceRoutes.radarrMovie(
      entry.mediaId,
      instanceId: entry.instanceId,
    ),
    ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
      entry.mediaId,
      instanceId: entry.instanceId,
    ),
    _ => ServiceRoutes.lidarrArtist(
      entry.mediaId,
      instanceId: entry.instanceId,
    ),
  });
}

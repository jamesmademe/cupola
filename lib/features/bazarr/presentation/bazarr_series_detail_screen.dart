import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_detail_view_model.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart'
    show BazarrDetailErrorState, BazarrDetailNotFoundState;
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// Bazarr series subtitle detail, on the shared media-detail scaffold.
class BazarrSeriesDetailScreen extends ConsumerWidget {
  const BazarrSeriesDetailScreen({
    super.key,
    required this.sonarrSeriesId,
    this.initialWanted,
  });

  final int sonarrSeriesId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.bazarr)) {
      // The missing-config marker, which the placeholder turns into
      // "Bazarr is not set up".
      return const BazarrDetailErrorState(
        error: ServiceNotConfigured(ServiceKey.bazarr),
      );
    }

    final seriesAsync = ref.watch(bazarrSeriesByIdProvider(sonarrSeriesId));
    final wantedAsync = ref.watch(
      bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
    );
    final series = seriesAsync.asData?.value;

    // Declared above the early returns so the failure and not-found states can
    // offer the same recovery the loaded page offers.
    void refresh() {
      ref.invalidate(bazarrSeriesByIdProvider(sonarrSeriesId));
      ref.invalidate(bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId));
    }

    if (series == null && initialWanted == null) {
      if (seriesAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.bazarr.accent,
          heroFallbackIcon: Icons.subtitles_outlined,
        );
      }
      if (seriesAsync.hasError) {
        return BazarrDetailErrorState(
          error: seriesAsync.error!,
          onRetry: refresh,
        );
      }
      // Bazarr learns about a series on its next Sonarr sync, so "not here yet"
      // is a state a retry can genuinely resolve.
      return BazarrDetailNotFoundState(
        icon: Icons.tv_off_rounded,
        title: 'Series not found in Bazarr',
        onRetry: refresh,
      );
    }

    final viewModel = BazarrDetailViewModel.forSeries(series, initialWanted);
    final accent = ServiceKey.bazarr.accent;
    // The lookup failed and the page stands on the wanted episode it was
    // opened from: see the movie screen.
    final lookupFailure = series == null && seriesAsync.hasError
        ? seriesAsync.error
        : null;
    final wantedItems = wantedAsync.asData?.value ?? const <BazarrWantedItem>[];

    final refreshAction = IconButton(
      icon: const Icon(Icons.refresh_rounded, size: 20),
      // Names the side being re-read, the same way the Bazarr movie page does.
      tooltip: 'Refresh from Bazarr',
      onPressed: refresh,
    );
    const label = 'Missing subtitles';
    // How many episode rows follow: a different fact from the hero chip's
    // "N missing", so the same sentence is not printed twice.
    final count = wantedItems.isEmpty
        ? null
        : '${wantedItems.length} '
              '${wantedItems.length == 1 ? 'episode' : 'episodes'}';

    return MediaDetailView(
      accent: accent,
      title: viewModel.title,
      heroFallbackIcon: Icons.subtitles_outlined,
      // The spine owns the indicator and the always-scrollable physics now, so
      // there is exactly one claimant on the pull gesture.
      onRefresh: () async => refresh(),
      posterRow: MediaDetailPosterRow(
        statusBadge: StatusBadge.animated(info: viewModel.status),
        title: viewModel.title,
        metadataItems: [if (series?.year != null) '${series!.year}'],
        tags: [
          Semantics(
            label: viewModel.missingChipSpoken,
            excludeSemantics: true,
            child: TagChip(text: viewModel.missingChip, color: accent),
          ),
        ],
        posterCard: MediaDetailFigurePlate(
          value: viewModel.missingFigure,
          label: 'Missing',
          accent: accent,
        ),
      ),
      body: MediaDetailBody(
        // See the movie screen for why the readout region carries it.
        readout: lookupFailure == null
            ? null
            : InlineErrorRetry(
                message: sectionFailureMessage(
                  ServiceKey.bazarr,
                  lookupFailure,
                  consequence: 'the series record is missing from this page',
                ),
                error: lookupFailure,
                service: ServiceKey.bazarr,
                onRetry: refresh,
              ),
        // Bazarr's column, one region short of the drawn one. The board gives
        // the wide track an episode x language chip table and demotes this
        // wanted list to the 380 column beside it; the table needs
        // `GET /api/episodes?seriesid[]=`, which this client cannot ask for, so
        // the list *is* the page and holds the wide track until it can. Details
        // and Tags stand aside either way.
        sideTrack: const {'Details', 'Tags'},
        // Region 2: the manifest. The lazy episode list used to be handed to the
        // view as a sliver while the states went in as content sections, and the
        // old spine emitted every content section first, so these rows rendered
        // *after* Details and Tags. A named region makes that unreachable while
        // keeping the list lazy: a heavily-wanted series builds the rows on
        // screen, not all of them.
        operate: [
          if (wantedItems.isEmpty)
            MediaDetailSlot.box(
              label: label,
              count: count,
              labelAction: refreshAction,
              child: wantedAsync.when(
                data: (items) => AppEmptyState.compact(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'All languages covered',
                  message: 'No missing subtitles for this series.',
                  // Raw `AppColors.success` is 2.07:1 on paper: the one mark
                  // on a screen whose whole message is "nothing is missing"
                  // was the one a daylight reader could not see.
                  accentColor: statusToneColor(
                    Theme.of(context).colorScheme,
                    StatusTone.success,
                  ),
                ),
                loading: () => ShimmerList(itemCount: 3, itemHeight: 56),
                // Under the page's line the silence is already said: see the
                // movie screen. One wanted episode is not the series' list, so
                // the section names the gap rather than drawing it.
                error: (error, _) => lookupFailure != null
                    ? const BazarrAwaitingNote(
                        message:
                            'The wanted episodes appear here once Bazarr '
                            'sends them.',
                      )
                    : AppErrorState.compact(
                        error: error,
                        serviceName: 'Bazarr',
                        service: ServiceKey.bazarr,
                        onRetry: () => ref.invalidate(
                          bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
                        ),
                      ),
              ),
            )
          else
            MediaDetailSlot.lazy(
              label: label,
              count: count,
              labelAction: refreshAction,
              sliver: SliverList.builder(
                itemCount: wantedItems.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: BazarrWantedEpisodeTile(item: wantedItems[index]),
                ),
              ),
            ),
        ],
        reference: [
          if (viewModel.facts.isNotEmpty)
            MediaDetailSlot.box(
              label: 'Details',
              child: AppCard.surfaceOutlined(
                child: MediaFactsList(facts: viewModel.facts),
              ),
            ),
          if (viewModel.tags.isNotEmpty)
            MediaDetailSlot.box(
              // Real Bazarr tags, so the word is true here.
              label: 'Tags',
              child: MediaChipSection.accented(
                values: viewModel.tags,
                accent: accent,
              ),
            ),
        ],
      ),
    );
  }
}

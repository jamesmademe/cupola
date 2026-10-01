import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_action_buttons.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_release_facts.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_seasons_list.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_watch_providers.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DiscoverDetailScreen extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final String heroTag;
  final String? initialPosterUrl;

  const DiscoverDetailScreen({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.heroTag,
    this.initialPosterUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before any provider: with no Seerr the lookup below can only throw, and
    // a lookup that throws is asked again on a backoff no waiting can answer.
    if (!watchSeerrConfigured(ref)) return const SeerrDetailNotSetUpView();

    final normalizedMediaType = mediaType == 'movie' ? 'movie' : 'tv';
    final region = ref.watch(regionProvider);
    final detailsAsync = ref.watch(
      discoverDetailProvider((id: mediaId, type: normalizedMediaType)),
    );

    final hasInitialPoster =
        initialPosterUrl != null && initialPosterUrl!.isNotEmpty;

    final heroFallbackIcon = normalizedMediaType == 'movie'
        ? Icons.movie_outlined
        : Icons.tv_rounded;

    return detailsAsync.when(
      loading: () => MediaDetailLoadingView(
        accent: ServiceKey.seerr.accent,
        heroFallbackIcon: heroFallbackIcon,
        // Guard against an empty (non-null) poster URL: ImageUtils returns ''
        // when there is no posterPath, which would otherwise spawn a blank
        // destination Hero with no source counterpart and fade in.
        posterCard: hasInitialPoster
            ? MediaPosterCard(
                heroTag: heroTag,
                imageUrl: initialPosterUrl,
                fallbackIcon: heroFallbackIcon,
              )
            : null,
        backdropPosterUrl: hasInitialPoster ? initialPosterUrl : null,
      ),
      error: (error, stackTrace) => MediaDetailPlaceholderView.error(
        error: error,
        serviceName: 'Seerr',
        accent: ServiceKey.seerr.accent,
        // Recover in place: re-run the very lookup that failed.
        onRetry: () => ref.invalidate(
          discoverDetailProvider((id: mediaId, type: normalizedMediaType)),
        ),
      ),
      data: (details) {
        final viewModel = DiscoverDetailViewModel.fromResponse(
          details,
          initialPosterUrl: initialPosterUrl,
        );
        // The server's own numbering for its codes: Seerr's 6 is a barred
        // title and Overseerr's a deleted one. Until it has said, a 6 reads
        // as neither.
        final numbering = ref.watch(seerrNumberingProvider).value;
        final isMovie = normalizedMediaType == 'movie';
        final extrasAsync = ref.watch(
          discoverDetailExtrasProvider((
            mediaId: mediaId,
            mediaType: normalizedMediaType,
            tvdbId: viewModel.tvdbId,
            voteAverage: viewModel.voteAverage,
          )),
        );
        final extras =
            extrasAsync.asData?.value ??
            (isInLibrary: null, libraryCheckDone: false, lookupRatings: null);
        final watchProviders = viewModel.watchProvidersForRegion(region);
        final contentRating = isMovie
            ? viewModel.movieContentRatingForRegion(region)
            : viewModel.tvContentRatingForRegion(region);
        final regionReleases = viewModel.releasesForRegion(region);
        // The certification joins the metadata line as plain text rather than a
        // bordered chip. As a chip it was visually indistinguishable from a genre
        // beside it, so an "R" read as a genre called R.
        final metadataItems = [
          viewModel.year,
          if (contentRating != null && contentRating.isNotEmpty) contentRating,
          if (isMovie) viewModel.runtimeStr,
          if (!isMovie && viewModel.runtimeStr != null) viewModel.runtimeStr,
        ].whereType<String>().where((value) => value.isNotEmpty).toList();

        // Null when Cupola could not say: the service is not set up here, the
        // check is still out, or it failed. The deck tells those apart from a
        // no, which is the one answer that takes the Open jump away.
        final isInService = extras.libraryCheckDone ? extras.isInLibrary : null;

        // The hero chip slot's one meaning, here as everywhere: how much of the
        // manifest exists. The episode/season summary moved out of the metadata
        // line into it, and the genres moved down to the catalogue block.
        final manifestCounter = isMovie ? null : viewModel.episodeSummary;
        final ratingWidgets = _buildRatingWidgets(
          viewModel,
          extras.lookupRatings,
        );

        final accent = ServiceKey.seerr.accent;

        return MediaDetailView(
          accent: accent,
          heroFallbackIcon: heroFallbackIcon,
          posterUrl: viewModel.posterUrl,
          backdropUrl: viewModel.backdropUrl,
          title: viewModel.title,
          posterRow: MediaDetailPosterRow(
            statusBadge: _SeerrStatusBadges(
              standard: seerrMediaStatus(
                viewModel.mediaInfo,
                numbering: numbering,
              ),
              uhd: seerr4kMediaStatus(
                viewModel.mediaInfo,
                numbering: numbering,
              ),
            ),
            title: viewModel.title,
            metadataItems: metadataItems,
            tags: [
              if (manifestCounter != null && manifestCounter.isNotEmpty)
                TagChip(text: manifestCounter, color: accent),
            ],
            posterCard: MediaPosterCard(
              heroTag: heroTag,
              imageUrl: viewModel.posterUrl,
              fallbackIcon: heroFallbackIcon,
            ),
          ),
          // The same pair the retry path re-runs.
          onRefresh: () async {
            ref.invalidate(
              discoverDetailProvider((id: mediaId, type: normalizedMediaType)),
            );
            ref.invalidate(
              discoverDetailExtrasProvider((
                mediaId: mediaId,
                mediaType: normalizedMediaType,
                tvdbId: viewModel.tvdbId,
                voteAverage: viewModel.voteAverage,
              )),
            );
          },
          body: MediaDetailBody(
            deck: DiscoverActionButtons(
              mediaId: mediaId,
              mediaType: normalizedMediaType,
              hasManageableMedia: viewModel.hasManageableMedia,
              isInService: isInService,
              requestGate: seerrRequestGate(
                viewModel.mediaInfo,
                isMovie: isMovie,
                seasons: viewModel.seasons,
                numbering: numbering,
              ),
              tvdbId: viewModel.tvdbId,
              mediaInfo: viewModel.mediaInfo,
              title: viewModel.title,
              voteAverage: viewModel.voteAverage,
              videos: viewModel.hasRelatedVideos
                  ? viewModel.playableVideos
                  : const [],
            ),
            // Region 3 — the manifest. For a show that is the seasons Seerr
            // knows about, checked against what is already in the library.
            operate: [
              if (viewModel.hasSeasons)
                MediaDetailSlot.lazy(
                  label: 'Seasons',
                  count: manifestCounter,
                  // A lazy sliver mid-page: a 40-season show builds the rows on
                  // screen instead of every episode of every season.
                  sliver: DiscoverSeasonsList(
                    seasons: viewModel.seasons,
                    seasonStatuses: seerrSeasonStatuses(
                      viewModel.mediaInfo,
                      viewModel.seasons,
                      numbering: numbering,
                    ),
                  ),
                ),
            ],
            synopsis: [
              if (viewModel.overview.isNotEmpty)
                MediaDetailSlot.box(
                  label: 'Overview',
                  child: MediaProseSection(
                    text: viewModel.overview,
                    accent: accent,
                  ),
                ),
            ],
            reference: [
              MediaDetailSlot.box(
                label: 'Details',
                child: isMovie
                    ? DiscoverReleaseInfoCard.movie(
                        releases: regionReleases,
                        region: region,
                        studios: viewModel.studios,
                        directors: viewModel.directors,
                        writers: viewModel.writers,
                      )
                    : DiscoverReleaseInfoCard.tv(
                        firstAirDate: viewModel.firstAirDate,
                        lastAirDate: viewModel.lastAirDate,
                        nextEpisodeToAir: viewModel.nextEpisodeToAir,
                        studios: viewModel.studios,
                        directors: viewModel.directors,
                        writers: viewModel.writers,
                        networks: viewModel.networks,
                      ),
              ),
              // Region 5 and not region 6: where a title streams is a fact
              // about *this* title, and one that can settle the request outright
              // — "I already pay for that" is an answer, not an afterthought.
              // Sitting last under Cast and Collection put it among the other
              // titles, three screens below the button it should have informed.
              // No slot at all when the region has nothing: a heading over "not
              // available in your region" is a section that reports its own
              // absence.
              if (watchProviders != null && watchProviders.hasAny)
                MediaDetailSlot.box(
                  label: 'Where to watch',
                  child: DiscoverWatchProviders(providers: watchProviders),
                ),
              if (ratingWidgets.isNotEmpty)
                MediaDetailSlot.box(
                  label: 'Scores',
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: ratingWidgets,
                  ),
                ),
              if (viewModel.genresList.isNotEmpty)
                MediaDetailSlot.box(
                  label: 'Genres',
                  child: MediaChipSection.neutral(values: viewModel.genresList),
                ),
              if (viewModel.keywords.isNotEmpty)
                MediaDetailSlot.box(
                  // TMDB keywords, and they are labelled as such. The old
                  // heading said "Tags", which in this domain names a real
                  // Radarr/Sonarr concept the app also surfaces — so it asserted
                  // something false about the user's server.
                  label: 'Keywords',
                  child: MediaChipSection.neutral(values: viewModel.keywords),
                ),
            ],
            related: [
              if (viewModel.cast.isNotEmpty)
                MediaDetailSlot.rail(
                  label: 'Cast',
                  // The rail takes the resolved gutter so its first face aligns
                  // to the content column while the row bleeds past it.
                  builder: (padding) =>
                      DiscoverCastList(cast: viewModel.cast, padding: padding),
                ),
              if (viewModel.hasCollection)
                MediaDetailSlot.box(
                  label: 'Collection',
                  child: DiscoverCollectionBanner(
                    collection: viewModel.collection!,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static List<Widget> _buildRatingWidgets(
    DiscoverDetailViewModel viewModel,
    List<DiscoverDetailRating>? lookupRatings,
  ) {
    if (lookupRatings != null) {
      return lookupRatings
          // A 0.0 with no votes is "not rated yet", not a score of zero.
          .where((rating) => rating.value > 0 || rating.votes > 0)
          .map((rating) {
            // These ratings come from a Radarr/Sonarr lookup, so they arrive
            // badged `MC` / `RO` / `TR` exactly as they do on the library pages.
            // One label per source, resolved the same way there, so the same
            // score is named identically on both pages.
            final label = ratingSourceLabel(
              icon: rating.icon,
              name: rating.name,
            );
            final display = ratingDisplayFor(
              icon: rating.icon,
              name: rating.name,
              value: rating.value,
            );
            return RatingChip(
              value: display.value,
              denominator: display.denominator,
              votes: rating.votes,
              sourceName: label,
              sourceIcon: label,
            );
          })
          .toList(growable: false);
    }

    final voteAverage = viewModel.voteAverage;
    if (voteAverage == null || voteAverage <= 0) {
      return const [];
    }

    return [
      RatingChip(
        value: voteAverage.toStringAsFixed(1),
        // TMDB's own scale, stated for the same reason every other pill states
        // its own: this number is a 0–10 and the row it sits in is not uniform.
        denominator: '/10',
        votes: viewModel.voteCount ?? 0,
        sourceName: 'TMDB',
        sourceIcon: 'TMDB',
      ),
    ];
  }
}

/// The title's state in Seerr: the standard copy, and beside it the 4K copy
/// when Seerr holds one.
///
/// Two of the same badge rather than one carrying both: each resolution has
/// its own state and its own tone, and a title on disk in HD with its 4K
/// copy still waiting for approval is both of those at once.
class _SeerrStatusBadges extends StatelessWidget {
  const _SeerrStatusBadges({required this.standard, required this.uhd});

  final MediaStatusInfo standard;
  final MediaStatusInfo? uhd;

  @override
  Widget build(BuildContext context) {
    final uhd = this.uhd;
    if (uhd == null) return StatusBadge.animated(info: standard);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        StatusBadge.animated(info: standard),
        StatusBadge.animated(info: uhd),
      ],
    );
  }
}

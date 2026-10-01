import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_detail_view_model.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Bazarr movie subtitle detail, on the shared media-detail scaffold.
class BazarrMovieDetailScreen extends ConsumerWidget {
  const BazarrMovieDetailScreen({
    super.key,
    required this.radarrId,
    this.initialWanted,
  });

  final int radarrId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.bazarr)) {
      // The missing-config marker, which the placeholder turns into
      // "Bazarr is not set up".
      return const BazarrDetailErrorState(error: 'Bazarr not configured');
    }

    final movieAsync = ref.watch(bazarrMovieByIdProvider(radarrId));
    final wantedAsync = ref.watch(bazarrWantedMovieByIdProvider(radarrId));
    final movie = movieAsync.asData?.value;

    // Declared above the early returns so the failure and not-found states can
    // offer the same recovery the loaded page offers.
    void refresh() {
      ref.invalidate(bazarrMovieByIdProvider(radarrId));
      ref.invalidate(bazarrWantedMovieByIdProvider(radarrId));
    }

    if (movie == null && initialWanted == null) {
      if (movieAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.bazarr.accent,
          heroFallbackIcon: Icons.subtitles_outlined,
        );
      }
      if (movieAsync.hasError) {
        return BazarrDetailErrorState(
          error: movieAsync.error!,
          onRetry: refresh,
        );
      }
      // Bazarr learns about a movie on its next Radarr sync, so "not here yet"
      // is a state a retry can genuinely resolve.
      return BazarrDetailNotFoundState(
        icon: Icons.movie_filter_rounded,
        title: 'Movie not found in Bazarr',
        onRetry: refresh,
      );
    }

    final viewModel = BazarrDetailViewModel.forMovie(movie, initialWanted);
    final accent = ServiceKey.bazarr.accent;
    // The lookup failed and the page stands on the wanted item it was opened
    // from. That item names the languages, not the record: the figure, the
    // subtitles on disk and the details are Bazarr's, and they read as
    // unknown. Said, so a dash is not the only trace of a failure.
    final lookupFailure = movie == null && movieAsync.hasError
        ? movieAsync.error
        : null;

    return MediaDetailView(
      accent: accent,
      title: viewModel.title,
      // Bazarr has no artwork of its own, so the fallback glyph is the hero's
      // only art and it must be Bazarr's, not a film reel.
      heroFallbackIcon: Icons.subtitles_outlined,
      // The spine owns the indicator, the always-scrollable physics and the
      // reconciliation with the hero's overscroll stretch, so this screen no
      // longer wraps its own.
      onRefresh: () async => refresh(),
      posterRow: MediaDetailPosterRow(
        statusBadge: StatusBadge.animated(info: viewModel.status),
        title: viewModel.title,
        // Year only: the missing count is the figure plate and the chip below,
        // so it is not also a third item in the metadata line.
        metadataItems: [if (movie?.year != null) '${movie!.year}'],
        tags: [
          Semantics(
            label: viewModel.missingChipSpoken,
            excludeSemantics: true,
            child: TagChip(text: viewModel.missingChip, color: accent),
          ),
        ],
        // Bazarr has no poster *by definition*, so the 82x123 slot carried a
        // fake one rendering a film reel. It now carries the page's own figure.
        posterCard: MediaDetailFigurePlate(
          value: viewModel.missingFigure,
          label: 'Missing',
          accent: accent,
        ),
      ),
      body: MediaDetailBody(
        // The top of the body on a page with no deck, and the region whose
        // padding a line of this kind is drawn for: its first glyph lands on
        // the column edge.
        readout: lookupFailure == null
            ? null
            : InlineErrorRetry(
                message: sectionFailureMessage(
                  ServiceKey.bazarr,
                  lookupFailure,
                  consequence: 'the movie record is missing from this page',
                ),
                error: lookupFailure,
                onRetry: refresh,
              ),
        // The board's wide track is the per-language subtitle table and the file
        // Radarr reports; both need Bazarr write and read endpoints this client
        // has none of, so the missing-subtitle list holds it. Details and Tags
        // stand aside.
        sideTrack: const {'Details', 'Tags'},
        // Region 1 wants Bazarr's own promoted action ('Refresh from Bazarr'
        // while anything is missing). Until a Bazarr action resolver exists the
        // refresh lives on the section label, where the spine documents a
        // refresh control as belonging, and on the pull gesture above.
        // Region 3 — the manifest, and the only question this page exists to
        // answer. It used to render *after* Details and Tags, because the old
        // spine emitted every content section before every sliver.
        operate: [
          // The other half of "English, Italian · German wanted". Bazarr sends
          // the languages on disk with every movie record, and the page used to
          // read only the missing half, so a covered movie could say that it was
          // covered and never by what.
          if (viewModel.present.isNotEmpty)
            MediaDetailSlot.box(
              label: 'Subtitles on disk',
              child: BazarrSubtitleLanguageWrap(languages: viewModel.present),
            ),
          MediaDetailSlot.box(
            label: 'Missing subtitles',
            // No count: the hero chip already states the missing figure in
            // words, and the language pills below are the detail.
            labelAction: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              // Names the side being re-read. A bare "Refresh" on a page whose
              // whole subject is what another service has not done yet leaves
              // the user guessing whether it re-checks Bazarr or asks Bazarr to
              // go hunting.
              tooltip: 'Refresh from Bazarr',
              onPressed: refresh,
            ),
            child: wantedAsync.when(
              data: (item) {
                if (item == null) {
                  return AppEmptyState.compact(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'All languages covered',
                    message: 'No missing subtitles for this movie.',
                    // See the series screen: the success green only clears AA
                    // once it is walked against the ground it lands on.
                    accentColor: statusToneColor(
                      Theme.of(context).colorScheme,
                      StatusTone.success,
                    ),
                  );
                }
                if (item.missingLanguages.isEmpty) {
                  // Bazarr filed this movie as wanted but named no languages —
                  // "No language data available" reported the app's own gap
                  // rather than the server's, and gave a self-hoster nothing to
                  // check.
                  return const AppEmptyState.compact(
                    icon: Icons.language_rounded,
                    title: 'No languages listed',
                    message:
                        'Bazarr is looking for subtitles here but did not say '
                        'which languages are missing. Check the language '
                        'profile on this movie in Bazarr.',
                  );
                }
                return BazarrSubtitleLanguageWrap(
                  languages: item.missingLanguages,
                );
              },
              loading: () => ShimmerList(itemCount: 2, itemHeight: 56),
              // Under the page's line the silence is already said, so this
              // section shows what the wanted row it was opened from named,
              // and says nothing again. Alone, its own failure is its own.
              error: (error, _) => lookupFailure != null
                  ? _wantedFallback(initialWanted)
                  : AppErrorState.compact(
                      error: error,
                      serviceName: 'Bazarr',
                      onRetry: () => ref.invalidate(
                        bazarrWantedMovieByIdProvider(radarrId),
                      ),
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
              // The one page in the app where this word is true: these are real
              // Bazarr tags off the user's server, not genres.
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

/// The missing languages the wanted row named, or a note when it named none.
Widget _wantedFallback(BazarrWantedItem? wanted) {
  final languages = wanted?.missingLanguages ?? const [];
  if (languages.isEmpty) {
    return const BazarrAwaitingNote(
      message: 'The missing languages appear here once Bazarr sends them.',
    );
  }
  return BazarrSubtitleLanguageWrap(languages: languages);
}

/// Error / not-configured state for the two Bazarr detail screens.
///
/// A thin alias over the shared [MediaDetailPlaceholderView] so both screens
/// name Bazarr and light the room in Bazarr's accent from one place.
class BazarrDetailErrorState extends StatelessWidget {
  const BazarrDetailErrorState({super.key, required this.error, this.onRetry});

  final Object error;

  /// Re-runs the failed load in place. Omitted for the not-configured case,
  /// whose fix is in Settings rather than another request.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MediaDetailPlaceholderView.error(
      error: error,
      serviceName: 'Bazarr',
      accent: ServiceKey.bazarr.accent,
      onRetry: onRetry,
    );
  }
}

/// The looked-up item does not exist in Bazarr — a normal state, not an
/// error, so it gets the empty-state voice rather than alarm chrome.
class BazarrDetailNotFoundState extends StatelessWidget {
  const BazarrDetailNotFoundState({
    super.key,
    required this.icon,
    required this.title,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MediaDetailPlaceholderView.notFound(
      icon: icon,
      title: title,
      message: 'Bazarr picks new titles up on its next sync with the -arrs.',
      serviceName: 'Bazarr',
      accent: ServiceKey.bazarr.accent,
      onRetry: onRetry,
    );
  }
}

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/media_info_card.dart';
import 'package:cupola/features/bazarr/domain/bazarr_subtitle_status.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// Presentation model for the Bazarr movie/series detail screens.
///
/// Owns the title-fallback cascade (library record → wanted item → constant)
/// and every derived display string, so both screens and their tests share
/// one resolution rule instead of re-deriving it per widget.
class BazarrDetailViewModel {
  final String title;
  final List<String> tags;
  final String? profileLabel;
  final MediaStatusInfo status;
  final List<MediaFact> facts;

  /// Subtitles Bazarr says are still outstanding, or null when this page does
  /// not know.
  ///
  /// Exposed rather than derived per screen: both screens need it three times
  /// over (the figure plate, the hero chip and the empty state), and each was
  /// re-deriving it from the same `movie ?? fallback` cascade this class already
  /// owns — two copies of one rule.
  ///
  /// **Null is not zero.** The cascade used to end in `?? 0`, so a series whose
  /// record lookup failed — opened from the wanted list, where the episode that
  /// brought the user here is itself a missing subtitle — read "0 Missing" over
  /// "All covered". Zero is a count Bazarr sent; null is a lookup that failed,
  /// is still running, or came back without the figure.
  final int? missing;

  /// Subtitles already on disk, one per language. Movies only: a series has one
  /// set per episode, which this page does not read.
  final List<BazarrSubtitleLanguage> present;

  /// Whether anything (library record or wanted fallback) exists to render.
  final bool found;

  /// The hero chip's words: `3 missing`, `All covered` only for a zero Bazarr
  /// actually sent, and `— missing` when the figure is unknown.
  String get missingChip => switch (missing) {
    null => '${Lexicon.noFigure} missing',
    0 => 'All covered',
    final n => '$n missing',
  };

  /// What a screen reader hears for the chip. The plate beside it is silent,
  /// so this is the figure's only voice — and a dash is spoken as what it
  /// means, never as "dash".
  String get missingChipSpoken =>
      missing == null ? 'Missing subtitles unknown' : missingChip;

  /// The figure plate's numeral.
  String get missingFigure => missing?.toString() ?? Lexicon.noFigure;

  const BazarrDetailViewModel._({
    required this.title,
    required this.tags,
    required this.profileLabel,
    required this.status,
    required this.facts,
    required this.missing,
    this.present = const [],
    required this.found,
  });

  factory BazarrDetailViewModel.forMovie(
    BazarrMovie? movie,
    BazarrWantedItem? fallback,
  ) {
    // The library record is the answer. Without it, the wanted item the user
    // came from still names its languages — but a wanted item naming none
    // says something is missing without saying how much, and that is not 0.
    final fallbackMissing = fallback?.missingSubtitlesCount ?? 0;
    final missing =
        movie?.missingSubtitlesCount ??
        (fallbackMissing > 0 ? fallbackMissing : null);
    final profileLabel = movie?.profileId != null
        ? 'Profile #${movie!.profileId}'
        : null;
    return BazarrDetailViewModel._(
      title: movie?.title ?? fallback?.title ?? 'Unknown movie',
      tags: movie?.tags ?? const [],
      profileLabel: profileLabel,
      status: bazarrSubtitleStatus(monitored: movie?.monitored),
      facts: [
        if (profileLabel != null) MediaFact('Profile', profileLabel),
        if (movie != null)
          MediaFact('Monitored', movie.monitored ? 'Yes' : 'No'),
        if ((movie?.path ?? '').isNotEmpty) MediaFact('Path', movie!.path!),
      ],
      missing: missing,
      present:
          movie?.presentLanguages ?? fallback?.presentLanguages ?? const [],
      found: movie != null || fallback != null,
    );
  }

  factory BazarrDetailViewModel.forSeries(
    BazarrSeries? series,
    BazarrWantedItem? fallback,
  ) {
    // Only the series record counts episodes: one wanted episode says at
    // least one is missing, never how many.
    final missing = series?.episodeMissingCount;
    final profileLabel = series?.profileId != null
        ? 'Profile #${series!.profileId}'
        : null;
    return BazarrDetailViewModel._(
      title: series?.title ?? fallback?.seriesTitle ?? 'Unknown series',
      tags: series?.tags ?? const [],
      profileLabel: profileLabel,
      status: bazarrSubtitleStatus(monitored: series?.monitored),
      facts: [
        if (profileLabel != null) MediaFact('Profile', profileLabel),
        if (series?.episodeCount != null)
          MediaFact('Episodes', '${series!.episodeCount}'),
        if (series != null)
          MediaFact('Monitored', series.monitored ? 'Yes' : 'No'),
        if ((series?.path ?? '').isNotEmpty) MediaFact('Path', series!.path!),
      ],
      missing: missing,
      found: series != null || fallback != null,
    );
  }
}

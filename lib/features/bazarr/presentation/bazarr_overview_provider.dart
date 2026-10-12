/// What the Bazarr Overview reads, and the pure functions that shape it.
///
/// Bazarr's work is **wanted subtitles**, and a wanted count is backlog, not a
/// fault: the five-arm tone rule paints it neutral, and this file is where that
/// is decided rather than in the widget that draws it.
///
/// Every shaping rule is a top-level pure function, so a row's composition and
/// its tone are testable without a container. The one thing missing here is a
/// *window*: Bazarr gives neither a wanted item's age nor a machine-readable
/// history timestamp (see [bazarrHistoryWhen]), so no section on this page
/// claims one.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wanted rows the section draws before the header's count is the only place
/// the rest are reported.
const int bazarrWantedPreviewLimit = 5;

/// Rows the History section draws.
const int bazarrHistoryPreviewLimit = 3;

/// One row of the Bazarr Overview.
@immutable
class BazarrOverviewRow {
  const BazarrOverviewRow({
    required this.headline,
    required this.detail,
    required this.tone,
  });

  /// `Severance S2 E4`, `Poor Things`.
  final String headline;

  /// `Italian · Sonarr`, `OpenSubtitles · score 94 · 20 min ago`.
  final String detail;

  final StatusTone tone;

  /// The row as one sentence, with the layout's `·` turned back into commas,
  /// in the headline too, which carries one on a history row.
  String get spoken =>
      joinSpokenParts([spokenFromDotted(headline), spokenFromDotted(detail)]);
}

/// A section's preview rows and the count they were cut from.
typedef BazarrOverviewSection = ({List<BazarrOverviewRow> rows, int total});

// ─── Wanted ─────────────────────────────────────────────────────────────────

/// `Severance S2 E4` for an episode, `Poor Things` for a movie.
///
/// Bazarr formats `episode_number` itself (`2x4`, or `S02E04`), so the code
/// is read back into its numbers and spelled the one way the app spells it
/// ([BazarrWantedItem.episodeCode]): two spellings of the same episode on one
/// screen is worse than either spelling.
String bazarrWantedHeadline(BazarrWantedItem item) {
  final series = item.seriesTitle?.trim();
  final code = item.episodeCode?.trim();
  if (series != null && series.isNotEmpty) {
    return code == null || code.isEmpty ? series : '$series $code';
  }
  final title = item.title?.trim();
  return title == null || title.isEmpty ? 'Unknown title' : title;
}

/// `Italian · Sonarr`.
///
/// **No age.** The board draws "missing 3 days", which Bazarr's wanted rows
/// cannot support: neither `/api/episodes/wanted` nor `/api/movies/wanted`
/// carries a date, so a figure there would have to be invented.
String bazarrWantedDetail(BazarrWantedItem item) => joinDisplayParts([
  bazarrMissingLanguagesLabel(item.missingLanguages),
  // Which arr owns the record, which is the one piece of provenance the row
  // does carry and the thing that decides where a fix would have to be made.
  if (item.sonarrSeriesId != null)
    'Sonarr'
  else if (item.radarrId != null)
    'Radarr'
  else
    null,
]);

/// `Italian`, `English forced`, `Italian, English`.
String bazarrMissingLanguagesLabel(List<BazarrSubtitleLanguage> languages) {
  final parts = <String>[];
  for (final language in languages) {
    final name = (language.name ?? language.code2 ?? language.code3)?.trim();
    if (name == null || name.isEmpty) continue;
    parts.add(
      joinDisplayParts([
        name,
        if (language.forced) 'forced',
        if (language.hi) 'HI',
      ], separator: ' '),
    );
  }
  return parts.join(', ');
}

/// The wanted preview, **neutral throughout**.
///
/// A wanted count is backlog: nothing is broken, Bazarr is simply still
/// looking. Painting it amber is the offence the tone rule exists to end: it
/// makes a working stack with a long tail look like a stack with a fault.
///
/// [total] is Bazarr's own badge count rather than the length of [items],
/// because the list is a page and the badge is the whole backlog.
BazarrOverviewSection bazarrWantedSection(
  List<BazarrWantedItem> items, {
  required int total,
  int limit = bazarrWantedPreviewLimit,
}) => (
  rows: List.unmodifiable([
    for (final item in items.take(limit))
      BazarrOverviewRow(
        headline: bazarrWantedHeadline(item),
        detail: bazarrWantedDetail(item),
        tone: StatusTone.neutral,
      ),
  ]),
  total: total,
);

// ─── History ────────────────────────────────────────────────────────────────

/// How a history entry reads.
///
/// Green for a subtitle that landed, informational for a match, **neutral for a
/// removal or a blacklisting**: blacklisting is a choice, not a fault, so no
/// amber appears in this list for it, and amber only for an event Bazarr
/// itself reported as failed.
StatusTone bazarrHistoryTone(BazarrHistoryItem item) {
  if (item.blacklisted) return StatusTone.neutral;
  return switch (item.action) {
    BazarrHistoryAction.downloaded ||
    BazarrHistoryAction.upgraded => StatusTone.success,
    BazarrHistoryAction.matched => StatusTone.info,
    BazarrHistoryAction.failed => StatusTone.warning,
    BazarrHistoryAction.removed ||
    BazarrHistoryAction.unknown => StatusTone.neutral,
  };
}

/// `Severance S2 E3 · Italian downloaded`.
String bazarrHistoryHeadline(BazarrHistoryItem item) {
  final title = item.title?.trim();
  final subject = title == null || title.isEmpty ? 'Unknown title' : title;
  final episode = item.kind == BazarrHistoryKind.episode
      ? item.subtitle?.trim()
      : null;
  final event = joinDisplayParts([
    item.languageLabel,
    item.action.label.toLowerCase(),
  ], separator: ' ');
  return joinDisplayParts([
    joinDisplayParts([subject, episode], separator: ', '),
    event,
  ]);
}

/// What Bazarr says about when, and nothing more.
///
/// Bazarr serves `timestamp` as a **pre-rendered** relative string ("20 min
/// ago") and `parsed_timestamp` as a locale-formatted `%x %X` with no timezone,
/// so the app cannot reconstruct an instant from either. The row therefore
/// quotes Bazarr's own words instead of computing an age, and no section on
/// this page is headed with a window it cannot honour.
String? bazarrHistoryWhen(BazarrHistoryItem item) {
  final pretty = item.timestamp?.trim();
  if (pretty != null && pretty.isNotEmpty) return pretty;
  final parsed = item.parsedTimestamp?.trim();
  return parsed == null || parsed.isEmpty ? null : parsed;
}

/// The history preview, newest first as Bazarr returned it.
List<BazarrOverviewRow> bazarrHistoryRows(
  List<BazarrHistoryItem> items, {
  int limit = bazarrHistoryPreviewLimit,
}) => List.unmodifiable([
  for (final item in items.take(limit))
    BazarrOverviewRow(
      headline: bazarrHistoryHeadline(item),
      detail: joinDisplayParts([
        item.provider,
        item.score == null ? null : 'score ${item.score}',
        bazarrHistoryWhen(item),
        if (item.blacklisted) 'blacklisted',
      ]),
      tone: bazarrHistoryTone(item),
    ),
]);

// ─── Providers ──────────────────────────────────────────────────────────────

/// The Overview's first region: the subtitles Bazarr is still looking for.
///
/// The badge count and the page are fetched together so the header's figure and
/// the rows under it describe the same moment.
final bazarrOverviewWantedProvider =
    FutureProvider.autoDispose<BazarrOverviewSection>((ref) async {
      final items = await ref.watch(bazarrDashboardWantedProvider.future);
      final badges = await ref.watch(bazarrBadgesProvider.future);
      return bazarrWantedSection(items, total: badges.totalWanted);
    });

/// The Overview's second region: what Bazarr did recently.
final bazarrOverviewHistoryProvider =
    FutureProvider.autoDispose<List<BazarrOverviewRow>>((ref) async {
      final items = await ref.watch(bazarrDashboardHistoryProvider.future);
      return bazarrHistoryRows(items);
    });

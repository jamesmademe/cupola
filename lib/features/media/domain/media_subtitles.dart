import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// What Bazarr says of a series' subtitles, in the page's words.

/// Subtitle languages by name, `English, Italian`, up to two; past two by
/// code, `EN · IT · DE`. Each once.
String mediaLanguageWords(Iterable<BazarrSubtitleLanguage> languages) {
  final distinct = <String, BazarrSubtitleLanguage>{};
  for (final language in languages) {
    final key = _keyOf(language);
    if (key.isNotEmpty) distinct.putIfAbsent(key, () => language);
  }
  if (distinct.length <= 2) {
    return distinct.values
        .map((language) => language.name ?? language.code2!.toUpperCase())
        .join(', ');
  }
  return mediaLanguageCodes(distinct.values);
}

/// Subtitle languages by their two-letter code, upper case, each once:
/// `EN · IT`.
String mediaLanguageCodes(Iterable<BazarrSubtitleLanguage> languages) =>
    languages
        .map(
          (language) => (language.code2 ?? language.name ?? '').toUpperCase(),
        )
        .where((code) => code.isNotEmpty)
        .toSet()
        .join(dotSeparator);

/// One episode's subtitles, `English on disk · Italian wanted`; null when
/// Bazarr has none on disk and wants none.
String? mediaEpisodeSubtitles(BazarrEpisode episode) {
  final present = mediaLanguageWords(episode.presentLanguages);
  final missing = mediaLanguageWords(episode.missingLanguages);
  final parts = [
    if (present.isNotEmpty) '$present on disk',
    if (missing.isNotEmpty) '$missing wanted',
  ];
  return parts.isEmpty ? null : parts.join(dotSeparator);
}

/// The languages a series has on disk wherever Bazarr looks for them: on
/// disk somewhere, and wanted nowhere. A language still wanted on an
/// episode is the series' wanted one, not its on-disk one.
List<BazarrSubtitleLanguage> mediaSeriesLanguagesOnDisk(
  List<BazarrEpisode> episodes,
) {
  final wanted = {
    for (final episode in episodes)
      for (final language in episode.missingLanguages) _keyOf(language),
  };
  return [
    for (final episode in episodes)
      for (final language in episode.presentLanguages)
        if (!wanted.contains(_keyOf(language))) language,
  ];
}

String _keyOf(BazarrSubtitleLanguage language) =>
    (language.code2 ?? language.name ?? '').toLowerCase();

/// Subtitles, closed: the languages on disk, then what is wanted and on how
/// many episodes, `EN · IT wanted on 3 episodes`.
String mediaSeriesSubtitlesSummary(List<BazarrEpisode> episodes) {
  final wanting = [
    for (final episode in episodes)
      if (episode.missingLanguages.isNotEmpty) episode,
  ];
  final present = mediaLanguageCodes(mediaSeriesLanguagesOnDisk(episodes));
  final missing = mediaLanguageCodes(
    wanting.expand((episode) => episode.missingLanguages),
  );
  return [
    if (present.isNotEmpty) present,
    if (missing.isNotEmpty)
      '$missing wanted on ${countLabel(wanting.length, 'episode')}',
  ].join(dotSeparator);
}

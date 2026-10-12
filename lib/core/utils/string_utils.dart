import 'package:cupola/core/utils/duration_format.dart';

/// Formats a whole number of minutes as `2h 7m`, or `47m` under the hour.
///
/// Radarr shipped `127 min` and Seerr `173min` for the same kind of fact. Hours
/// and minutes is the form a person actually reasons in ("do I have time for
/// this tonight?"), and it stops a three-digit minute count reading as a number
/// that needs dividing.
///
/// Returns an empty string for a non-positive value: a runtime of zero is a
/// fact the service does not have, not a film of no length, and an empty string
/// is dropped by the metadata line and the fact grid alike.
String formatRuntimeMinutes(int minutes) {
  if (minutes <= 0) return '';
  return formatTimeSpan(Duration(minutes: minutes));
}

/// Caps a service-supplied title so it can be interpolated into a sheet header
/// or a dialog title without pushing the controls off the screen.
///
/// Both destinations render an unbounded [Text]: the sheet header's subtitle has
/// no `maxLines`, and an `AlertDialog` title sits *above* the scrollable
/// content, so a long title grows the header until the buttons leave the
/// viewport. A user cannot shorten their own library, and a 200-character title
/// is a normal thing for an anime release or a documentary series to have; so
/// the caller shortens the string rather than trusting the layout to cope.
///
/// Cuts on a word boundary where there is one within reach, so the tail reads
/// as a truncated title rather than a truncated word, and appends a single
/// ellipsis glyph (not three periods, which read as a pause).
String truncateTitle(String value, {int maxChars = 64}) {
  final trimmed = value.trim();
  if (trimmed.length <= maxChars) return trimmed;

  final hardCut = trimmed.substring(0, maxChars);
  final lastSpace = hardCut.lastIndexOf(' ');
  // Only honour a word boundary in the last third; a title whose first word is
  // longer than the budget would otherwise collapse to a single ellipsis.
  final cut = lastSpace >= (maxChars * 2) ~/ 3
      ? hardCut.substring(0, lastSpace)
      : hardCut;

  return '${cut.trimRight()}…';
}

/// Capitalizes the first character of [value].
///
/// Returns [value] unchanged if it is empty.
String capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// Turns an API identifier into display text, in sentence case like every
/// other label: `importBlocked` → `Import blocked`, `download_client` →
/// `Download client`. A word the identifier already spells in capitals
/// (`IMDB_id`, `TVDB`) keeps them.
String humanizeCamelCase(String value) {
  if (value.trim().isEmpty) return value;

  final normalized = value.replaceAll('_', ' ').replaceAll('-', ' ');
  final withSpaces = normalized.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  final words = withSpaces
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  return [
    for (final (index, word) in words.indexed)
      if (index == 0)
        capitalizeFirst(word)
      else if (word.length > 1 && word == word.toUpperCase())
        word
      else
        '${word[0].toLowerCase()}${word.substring(1)}',
  ].join(' ');
}

/// `1 device` / `3 devices`: a count and its noun, pluralised the naive way.
///
/// Naive on purpose: every noun it is given is an English API noun the app
/// chose itself (device, user, item, playlist), never a translated or
/// user-supplied one, so the `s` is correct for all of them and an
/// irregular-plural table would be machinery for a case that cannot arrive.
/// It was written twice verbatim, in the Plex and Jellyfin tab screens.
String countLabel(int count, String noun) =>
    '$count ${count == 1 ? noun : '${noun}s'}';

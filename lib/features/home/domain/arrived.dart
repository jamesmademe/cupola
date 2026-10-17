/// The words of the Home's Arrived: what the libraries gained in the last
/// seven days, one card per title, the newest first.
///
/// A movie arrives when it is imported. A series arrives when it is new to
/// the library: a new episode of a series that was already there is Coming
/// up's and Continue watching's news, not a title that arrived. An album
/// arrives when its tracks are imported.
library;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart'
    show joinWithAnd;
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;

/// How many cards the rail draws; the line counts them all.
const arrivedCardLimit = 8;

/// One card per title among [entries], the newest import of each first,
/// leaving out what was imported before [since] and the episodes of a series
/// added to its library before it.
///
/// A movie on the HD and the 4K Radarr is one card, the newer copy's; a
/// series is one card however many episodes landed.
List<ArrHistoryEntry> arrivedOf(
  List<ArrHistoryEntry> entries, {
  required DateTime since,
}) {
  final inWindow = [
    for (final entry in entries)
      if (entry.at case final at? when !at.isBefore(since))
        if (entry.service != ServiceKey.sonarr || _newToLibrary(entry, since))
          entry,
  ]..sort((a, b) => b.at!.compareTo(a.at!));
  final seen = <String>{};
  return [
    for (final entry in inWindow)
      if (seen.add(arrivedIdentity(entry))) entry,
  ];
}

/// A series whose library does not say when it was added is kept: what
/// cannot be judged is not hidden.
bool _newToLibrary(ArrHistoryEntry entry, DateTime since) =>
    entry.mediaAddedAt == null || !entry.mediaAddedAt!.isBefore(since);

/// What makes two imports the same title: TMDB's id across connections,
/// else the connection's own id of the movie, the series or the album.
String arrivedIdentity(ArrHistoryEntry entry) => switch (entry.service) {
  ServiceKey.radarr when entry.tmdbId != null => 'movie:${entry.tmdbId}',
  ServiceKey.sonarr when entry.tmdbId != null => 'tv:${entry.tmdbId}',
  ServiceKey.lidarr =>
    'lidarr:${entry.instanceId}:${entry.unitId ?? entry.mediaId}',
  _ => '${entry.service.name}:${entry.instanceId}:${entry.mediaId}',
};

/// The line under the module's name: `Last 7 days · 4 new`, and with a
/// source that did not answer, who the count is from: `Last 7 days · 2 from
/// Radarr`. Never "this week": on a Monday, Sunday is last week.
String arrivedSubtitle(int count, SourceCoverage coverage) {
  const window = 'Last 7 days';
  if (coverage.isPartial) {
    final answered = [for (final source in coverage.answered) source.title]
      ..sort();
    if (answered.isNotEmpty) {
      return '$window\u00A0· $count from ${joinWithAnd(answered)}';
    }
  }
  return '$window\u00A0· $count new';
}

/// What a card says under its title: when it arrived, and which connection
/// it came to while the service has more than one: `2 h ago · Radarr 4K`.
String arrivedCardLine(ArrHistoryEntry entry, {required String when}) => [
  when,
  if (entry.connectionName case final name? when name.isNotEmpty)
    serviceWithConnection(entry.service, name, joiner: ' '),
].join(dotSeparator);

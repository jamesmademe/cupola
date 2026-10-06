import 'package:flutter/foundation.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What the calendar dates, each kind its chip and the service it comes from.
enum CalendarKind {
  movie('Movies', 'movies', ServiceKey.radarr),
  episode('Series', 'episodes', ServiceKey.sonarr),
  album('Music', 'albums', ServiceKey.lidarr),
  book('Books', 'books', ServiceKey.readarr);

  const CalendarKind(this.chip, this.plural, this.service);

  /// The chip that shows only this kind: `Series`.
  final String chip;

  /// The kind inside a sentence: `albums may be missing here`.
  final String plural;

  /// The service whose calendar dates this kind.
  final ServiceKey service;

  /// The kind [service]'s calendar dates, or null for a service with none.
  static CalendarKind? of(ServiceKey service) {
    for (final kind in values) {
      if (kind.service == service) return kind;
    }
    return null;
  }
}

/// What marks an episode out from the ones around it.
enum CalendarMark {
  premiere('premiere'),
  seasonFinale('season finale'),
  midseasonFinale('midseason finale'),
  seriesFinale('series finale');

  const CalendarMark(this.words);
  final String words;

  /// Sonarr's mark for [record]: its `finaleType`, else a premiere for the
  /// first episode of a season.
  static CalendarMark? of(Map<String, dynamic> record) {
    switch (stringOrNull(record['finaleType'])?.toLowerCase()) {
      case 'series':
        return seriesFinale;
      case 'season':
        return seasonFinale;
      case 'midseason':
        return midseasonFinale;
    }
    final season = intOrNull(record['seasonNumber']);
    return season != null &&
            season > 0 &&
            intOrNull(record['episodeNumber']) == 1
        ? premiere
        : null;
  }
}

/// Where a dated thing stands, from the furthest behind to the furthest on.
enum CalendarStand {
  /// Its day has not come: not out yet, not aired.
  notYet,

  /// Out, with nothing on disk; [CalendarState.missingKnown] says whether
  /// the queue was read whole, so that nothing in flight is a fact.
  out,

  /// Out and in the download queue.
  inFlight,

  /// On the server.
  onServer,
}

/// Where one dated thing stands on one connection, or merged across several.
@immutable
class CalendarState {
  const CalendarState.notYet()
    : stand = CalendarStand.notYet,
      queue = null,
      finishesAt = null,
      missingKnown = false;

  const CalendarState.onServer()
    : stand = CalendarStand.onServer,
      queue = null,
      finishesAt = null,
      missingKnown = false;

  /// Out with nothing on disk. [missingKnown] when the queue answered whole,
  /// so the thing is missing; otherwise it may be downloading right now.
  const CalendarState.out({required this.missingKnown})
    : stand = CalendarStand.out,
      queue = null,
      finishesAt = null;

  /// In the queue: [queue] is what the queue says of it.
  const CalendarState.inFlight(MediaStatusInfo this.queue, {this.finishesAt})
    : stand = CalendarStand.inFlight,
      missingKnown = false;

  final CalendarStand stand;

  /// The queue's word for it, while [stand] is [CalendarStand.inFlight].
  final MediaStatusInfo? queue;

  /// When the download says it will be done, when it says.
  final DateTime? finishesAt;

  final bool missingKnown;

  /// The tone of the dot: neutral for the backlog, blue or amber from the
  /// queue, green on the server.
  StatusTone get tone => switch (stand) {
    CalendarStand.notYet || CalendarStand.out => StatusTone.neutral,
    CalendarStand.inFlight => queue!.tone,
    CalendarStand.onServer => StatusTone.success,
  };

  /// A ring rather than a dot: a day that has not come asks nothing yet.
  bool get hollow => stand == CalendarStand.notYet;

  /// The download's percentage, while it is worth drawing.
  int? get percent => queue?.progressPercent;

  /// The word after the thing's own facts: `downloading 62%`, `on your
  /// server`, `missing`. [notYet] is the kind's (`not aired`, `not out
  /// yet`); [outWord] is what precedes `missing` (`out today`, `aired`).
  String words({required String notYet, required String outWord}) =>
      switch (stand) {
        CalendarStand.notYet => notYet,
        CalendarStand.out =>
          missingKnown ? '$outWord · ${StateWord.missing.inline}' : outWord,
        CalendarStand.inFlight => [
          Lexicon.inline(queue!.label),
          if (percent case final percent?) formatPercent(percent),
        ].join(' '),
        CalendarStand.onServer => 'on your server',
      };

  /// The furthest on of [a] and [b]: a thing on one server is on the
  /// server, whatever the other says.
  static CalendarState furthest(CalendarState a, CalendarState b) {
    if (b.stand.index > a.stand.index) return b;
    if (b.stand.index < a.stand.index) return a;
    // Two "out"s: missing only if every connection says so.
    if (a.stand == CalendarStand.out) {
      return CalendarState.out(missingKnown: a.missingKnown && b.missingKnown);
    }
    return a;
  }
}

/// What a row opens.
sealed class CalendarTarget {
  const CalendarTarget();
}

/// A movie's or a series' page.
final class CalendarMediaTarget extends CalendarTarget {
  const CalendarMediaTarget(this.key, {this.connectionId});
  final MediaKey key;

  /// The connection the row was read from, which leads on the page.
  final String? connectionId;

  @override
  bool operator ==(Object other) =>
      other is CalendarMediaTarget &&
      other.key == key &&
      other.connectionId == connectionId;

  @override
  int get hashCode => Object.hash(key, connectionId);
}

/// An artist's page on a Lidarr, or an author's on a Readarr.
final class CalendarShelfTarget extends CalendarTarget {
  const CalendarShelfTarget(this.service, this.connectionId, this.id);
  final ServiceKey service;
  final String connectionId;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is CalendarShelfTarget &&
      other.service == service &&
      other.connectionId == connectionId &&
      other.id == id;

  @override
  int get hashCode => Object.hash(service, connectionId, id);
}

/// One dated thing: a movie's release, an episode's airing, an album, a
/// book. One row of the calendar, whichever connections hold it.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.identity,
    required this.kind,
    required this.day,
    required this.title,
    required this.state,
    this.airsAt,
    this.release,
    this.season,
    this.episode,
    this.mark,
    this.byline,
    this.poster,
    this.sources = const [],
    this.note,
    this.target,
  });

  /// What makes two connections' records one row: the movie and the
  /// release, the series and the episode, the album, the book.
  final String identity;

  final CalendarKind kind;

  /// The day, a local midnight.
  final DateTime day;

  /// When an episode airs, on this device's clock. Movies, albums and books
  /// have a date and never a time.
  final DateTime? airsAt;

  /// The movie, the series, the album, the book.
  final String title;

  /// A movie's release: `in cinemas`, `on digital`, `on disc`.
  final String? release;

  final int? season;
  final int? episode;
  final CalendarMark? mark;

  /// The artist of an album, the author of a book.
  final String? byline;

  final ImageSource? poster;

  /// The connections that hold it, by name: `Radarr · Radarr 4K`.
  final List<String> sources;

  /// A line in the sources' place, for a reader who reads no service names.
  final String? note;

  final CalendarState state;
  final CalendarTarget? target;

  /// `S2 E5`, for an episode.
  String? get code => formatArrEpisodeCode(season, episode);

  /// Whether the thing's moment has passed at [now]: an episode by its
  /// airing, anything else by its day.
  static bool hasCome(DateTime day, DateTime? airsAt, DateTime now) =>
      airsAt != null
      ? !airsAt.isAfter(now)
      : !day.isAfter(DateTime(now.year, now.month, now.day));

  /// The lead column: an episode's time, or what kind of day it is
  /// (`Digital`, `Album`) over `all day`.
  ({String lead, String? under}) lead() {
    if (airsAt case final at?) return (lead: formatClockTime(at), under: null);
    final word = switch (kind) {
      CalendarKind.movie => switch (release) {
        Lexicon.inCinemas => 'Cinemas',
        Lexicon.onDisc => 'Disc',
        Lexicon.onDigital => 'Digital',
        _ => 'Movie',
      },
      CalendarKind.episode => 'Episode',
      CalendarKind.album => 'Album',
      CalendarKind.book => 'Book',
    };
    return (lead: word, under: 'all day');
  }

  /// The line under the title: what it is and where it stands. `S2 E5 ·
  /// premiere · not aired`, `Out today · downloading 62%`, `Jan Morgenstern ·
  /// not out yet`.
  String statusLine(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final outWord = day == today ? 'out today' : 'out';
    final String standing;
    switch (kind) {
      case CalendarKind.episode:
        standing = state.words(
          notYet: StateWord.notAired.inline,
          outWord: 'aired',
        );
        return [?code, ?mark?.words, standing].join(' · ');
      case CalendarKind.movie:
        // A movie on its day says it is out before what came of it; one on
        // the server says only that.
        standing = switch (state.stand) {
          CalendarStand.inFlight =>
            '$outWord · ${state.words(notYet: '', outWord: outWord)}',
          _ => state.words(
            notYet: StateWord.notOutYet.inline,
            outWord: outWord,
          ),
        };
        return _capitalised(standing);
      case CalendarKind.album:
      case CalendarKind.book:
        standing = switch (state.stand) {
          CalendarStand.inFlight =>
            '$outWord · ${state.words(notYet: '', outWord: outWord)}',
          _ => state.words(
            notYet: StateWord.notOutYet.inline,
            outWord: outWord,
          ),
        };
        return [?byline, standing].join(' · ');
    }
  }

  /// The row as one sentence for a screen reader: `Friday 2 October at
  /// 21:00, Cosmos Laundromat season 3 premiere, not aired yet, Sonarr`.
  String spoken(DateTime now) {
    final when = [
      spokenDay(day, now),
      if (airsAt case final at?) 'at ${formatClockTime(at)}',
    ].join(' ');
    final what = switch (kind) {
      CalendarKind.episode => [
        title,
        if (mark == CalendarMark.seriesFinale)
          'series finale'
        else ...[
          if (season != null) 'season $season',
          ?switch (mark) {
            CalendarMark.premiere => 'premiere',
            CalendarMark.seasonFinale => 'finale',
            CalendarMark.midseasonFinale => 'midseason finale',
            _ => episode == null ? null : 'episode $episode',
          },
        ],
      ].join(' '),
      CalendarKind.movie => [
        title,
        release == null || release == Lexicon.inCinemas
            ? 'movie ${release ?? 'out'}'
            : 'movie out $release',
      ].join(', '),
      CalendarKind.album => [
        title,
        'album${byline == null ? '' : ' by $byline'}',
      ].join(', '),
      CalendarKind.book => [
        title,
        'book${byline == null ? '' : ' by $byline'}',
      ].join(', '),
    };
    final standing = switch (state.stand) {
      CalendarStand.notYet =>
        kind == CalendarKind.episode ? 'not aired yet' : 'not out yet',
      CalendarStand.out =>
        state.missingKnown
            ? '${kind == CalendarKind.episode ? 'aired' : 'out'}, missing'
            : (kind == CalendarKind.episode ? 'aired' : 'out'),
      CalendarStand.inFlight => [
        [
          Lexicon.inline(state.queue!.label),
          if (state.percent case final p?) spokenPercent(p),
        ].join(' '),
        if (state.finishesAt case final at?)
          'ready around ${formatClockTime(at)}',
      ].join(', '),
      CalendarStand.onServer => 'on your server',
    };
    return [
      when,
      what,
      standing,
      if (sources.isNotEmpty) 'in ${joinWithAnd(sources)}',
      ?note,
    ].join(', ');
  }

  /// The furthest on of two connections' records of the same thing, each
  /// connection named once.
  CalendarEvent mergedWith(CalendarEvent other) => CalendarEvent(
    identity: identity,
    kind: kind,
    day: day,
    airsAt: airsAt ?? other.airsAt,
    title: title,
    release: release,
    season: season,
    episode: episode,
    mark: mark ?? other.mark,
    byline: byline ?? other.byline,
    poster: (poster?.url.isNotEmpty ?? false) ? poster : other.poster,
    sources: [
      ...sources,
      for (final source in other.sources)
        if (!sources.contains(source)) source,
    ],
    note: note ?? other.note,
    state: CalendarState.furthest(state, other.state),
    target: target ?? other.target,
  );
}

List<dynamic>? _list(Object? value) => value is List ? value : null;

String _capitalised(String words) =>
    words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);

/// `Radarr, Radarr 4K and Sonarr`.
String joinWithAnd(List<String> words) => switch (words.length) {
  0 => '',
  1 => words.single,
  _ => '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}',
};

/// The thirty days the calendar looks at, from today's local midnight to
/// the thirtieth day after it, both inclusive: what each arr is asked for.
@immutable
class CalendarWindow {
  CalendarWindow.from(DateTime now)
    : start = DateTime(now.year, now.month, now.day),
      end = DateTime(now.year, now.month, now.day + days);

  static const days = 30;

  final DateTime start;
  final DateTime end;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  @override
  bool operator ==(Object other) =>
      other is CalendarWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One connection's calendar as the arr sent it, and its queue when it was
/// needed: the raw records, so the mapping below stays pure.
@immutable
class CalendarReading {
  const CalendarReading({
    required this.service,
    required this.connectionId,
    required this.label,
    required this.records,
    this.queue,
    this.poster,
  });

  final ServiceKey service;
  final String connectionId;

  /// The connection's name, as the rows name it.
  final String label;

  final List<Map<String, dynamic>> records;

  /// The connection's queue, indexed by the id of what the calendar dates
  /// (a movie, an episode, an album, a book). Null when nothing in the
  /// calendar needed it: nothing out and off the disk.
  final ArrQueueSnapshot? queue;

  /// The artwork of a record's images, through the connection when it is
  /// the connection's own.
  final ImageSource? Function(List<dynamic>? images, List<String> coverTypes)?
  poster;
}

/// Whether any record of [records] from [service] is out with nothing on
/// disk at [now]: only then does the calendar need the queue.
bool calendarNeedsQueue(
  ServiceKey service,
  List<Map<String, dynamic>> records,
  CalendarWindow window,
  DateTime now,
) {
  for (final record in records) {
    for (final event in _eventsOf(
      CalendarReading(
        service: service,
        connectionId: '',
        label: '',
        records: const [],
      ),
      record,
      window,
      now,
    )) {
      if (event.state.stand == CalendarStand.out) return true;
    }
  }
  return false;
}

/// The calendar's rows from every connection's [readings]: one per dated
/// thing inside [window], each connection that holds it named on it, in date
/// order. Within a day the things with a date and no time lead (movies,
/// then albums, then books), then the episodes by their time.
List<CalendarEvent> libraryCalendarEvents(
  Iterable<CalendarReading> readings,
  CalendarWindow window,
  DateTime now,
) {
  final byIdentity = <String, CalendarEvent>{};
  for (final reading in readings) {
    for (final record in reading.records) {
      for (final event in _eventsOf(reading, record, window, now)) {
        byIdentity.update(
          event.identity,
          (held) => held.mergedWith(event),
          ifAbsent: () => event,
        );
      }
    }
  }
  return byIdentity.values.toList()..sort(compareCalendarEvents);
}

/// Date order; within a day, the dated things before the timed ones.
int compareCalendarEvents(CalendarEvent a, CalendarEvent b) {
  final byDay = a.day.compareTo(b.day);
  if (byDay != 0) return byDay;
  final aTimed = a.airsAt;
  final bTimed = b.airsAt;
  if (aTimed == null && bTimed != null) return -1;
  if (aTimed != null && bTimed == null) return 1;
  if (aTimed != null && bTimed != null) {
    final byTime = aTimed.compareTo(bTimed);
    if (byTime != 0) return byTime;
  }
  final byKind = a.kind.index.compareTo(b.kind.index);
  if (byKind != 0) return byKind;
  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (byTitle != 0) return byTitle;
  return (a.episode ?? 0).compareTo(b.episode ?? 0);
}

const _radarrReleases = [
  ('inCinemas', Lexicon.inCinemas),
  ('digitalRelease', Lexicon.onDigital),
  ('physicalRelease', Lexicon.onDisc),
];

/// The rows one record makes inside [window]: a movie one per release in
/// it, anything else one.
Iterable<CalendarEvent> _eventsOf(
  CalendarReading reading,
  Map<String, dynamic> record,
  CalendarWindow window,
  DateTime now,
) sync* {
  final service = reading.service;
  final kind = CalendarKind.of(service);
  if (kind == null) return;
  final id = intOrNull(record['id']);
  final queue = reading.queue;

  CalendarState stateOf({
    required DateTime day,
    DateTime? airsAt,
    required bool onDisk,
  }) {
    if (!CalendarEvent.hasCome(day, airsAt, now)) {
      return const CalendarState.notYet();
    }
    if (onDisk) return const CalendarState.onServer();
    final entry = queue?.entryFor(id);
    if (entry != null) {
      return CalendarState.inFlight(
        mediaStatusFromQueue(
          availability: MediaAvailability.missing,
          monitored: true,
          queueEntry: entry,
        ),
        finishesAt: entry.finishesAt,
      );
    }
    return CalendarState.out(missingKnown: queue?.isWhole ?? false);
  }

  ImageSource? art(List<dynamic>? images, List<String> types) {
    final resolved = reading.poster?.call(images, types);
    if (resolved != null) return resolved.url.isEmpty ? null : resolved;
    for (final type in types) {
      for (final image in images ?? const []) {
        final map = mapOrNull(image);
        if (map?['coverType'] != type) continue;
        final remote = stringOrNull(map?['remoteUrl']);
        if (remote != null && remote.startsWith('http')) {
          return (url: remote, headers: null);
        }
      }
    }
    return null;
  }

  final sources = [if (reading.label.isNotEmpty) reading.label];

  switch (kind) {
    case CalendarKind.movie:
      final title = stringOrNull(record['title']) ?? 'Movie';
      final tmdb = intOrNull(record['tmdbId']);
      final poster = art(_list(record['images']), const ['poster']);
      for (final (field, release) in _radarrReleases) {
        final day = arrCalendarDate(record[field]);
        if (day == null || !window.contains(day)) continue;
        yield CalendarEvent(
          identity: 'movie:${tmdb ?? title.toLowerCase()}:$field',
          kind: kind,
          day: day,
          title: title,
          release: release,
          poster: poster,
          sources: sources,
          state: stateOf(day: day, onDisk: record['hasFile'] == true),
          target: tmdb == null || tmdb <= 0
              ? null
              : CalendarMediaTarget(
                  MediaKey.movie(tmdb),
                  connectionId: reading.connectionId,
                ),
        );
      }
    case CalendarKind.episode:
      final airsAt = DateTime.tryParse(
        stringOrNull(record['airDateUtc']) ?? '',
      )?.toLocal();
      final day = airsAt == null
          ? arrCalendarDate(record['airDate'])
          : DateTime(airsAt.year, airsAt.month, airsAt.day);
      if (day == null || !window.contains(day)) return;
      final series = mapOrNull(record['series']);
      final title = stringOrNull(series?['title']) ?? 'Series';
      final tvdb = intOrNull(series?['tvdbId']);
      final tmdb = intOrNull(series?['tmdbId']);
      final season = intOrNull(record['seasonNumber']);
      final episode = intOrNull(record['episodeNumber']);
      yield CalendarEvent(
        identity:
            'episode:${tvdb ?? title.toLowerCase()}:${season ?? '-'}:'
            '${episode ?? stringOrNull(record['title']) ?? '-'}',
        kind: kind,
        day: day,
        airsAt: airsAt,
        title: title,
        season: season,
        episode: episode,
        mark: CalendarMark.of(record),
        poster: art(_list(series?['images']), const ['poster']),
        sources: sources,
        state: stateOf(
          day: day,
          airsAt: airsAt,
          onDisk: record['hasFile'] == true,
        ),
        target: switch ((tvdb, tmdb)) {
          (final tvdb?, _) when tvdb > 0 => CalendarMediaTarget(
            MediaKey.tvdb(tvdb),
            connectionId: reading.connectionId,
          ),
          (_, final tmdb?) when tmdb > 0 => CalendarMediaTarget(
            MediaKey.tv(tmdb),
            connectionId: reading.connectionId,
          ),
          _ => null,
        },
      );
    case CalendarKind.album:
    case CalendarKind.book:
      final day = arrCalendarDate(record['releaseDate']);
      if (day == null || !window.contains(day)) return;
      final album = kind == CalendarKind.album;
      final parent = mapOrNull(record[album ? 'artist' : 'author']);
      final parentId =
          intOrNull(record[album ? 'artistId' : 'authorId']) ??
          intOrNull(parent?['id']);
      final title = stringOrNull(record['title']) ?? (album ? 'Album' : 'Book');
      final statistics = mapOrNull(record['statistics']);
      final files = intOrNull(
        statistics?[album ? 'trackFileCount' : 'bookFileCount'],
      );
      final foreign = stringOrNull(
        record[album ? 'foreignAlbumId' : 'foreignBookId'],
      );
      yield CalendarEvent(
        identity: '${kind.name}:${foreign ?? '${title.toLowerCase()}:$day'}',
        kind: kind,
        day: day,
        title: title,
        byline: stringOrNull(parent?[album ? 'artistName' : 'authorName']),
        poster:
            art(_list(record['images']), const ['cover', 'poster']) ??
            art(_list(parent?['images']), const ['poster', 'cover']),
        sources: sources,
        state: stateOf(day: day, onDisk: (files ?? 0) > 0),
        target: parentId == null || reading.connectionId.isEmpty
            ? null
            : CalendarShelfTarget(service, reading.connectionId, parentId),
      );
  }
}

/// One entry of the agenda: a day with its rows, a quiet stretch, or the
/// end of the thirty days.
sealed class AgendaEntry {
  const AgendaEntry();
}

/// A day that has something, and its rows.
final class AgendaDay extends AgendaEntry {
  const AgendaDay(this.day, this.events);
  final DateTime day;
  final List<CalendarEvent> events;
}

/// Three or more days in a row with nothing: one quiet line, `Nothing until
/// Wed 21 Oct`.
final class AgendaGap extends AgendaEntry {
  const AgendaGap(this.until);

  /// The next day that has something.
  final DateTime until;
}

/// `Nothing more in the next 30 days`.
final class AgendaEnd extends AgendaEntry {
  const AgendaEnd();
}

/// How many empty days in a row read as a line of their own; fewer are
/// skipped without a word.
const calendarQuietRun = 3;

/// [events] (sorted, inside [window]) as the agenda lays them out: each day
/// that has something under its heading, a run of [calendarQuietRun] or more
/// empty days as one quiet line, and the end of the window.
List<AgendaEntry> calendarAgenda(
  List<CalendarEvent> events,
  CalendarWindow window,
) {
  final entries = <AgendaEntry>[];
  var previous = DateTime(
    window.start.year,
    window.start.month,
    window.start.day - 1,
  );
  final days = <DateTime, List<CalendarEvent>>{};
  for (final event in events) {
    (days[event.day] ??= []).add(event);
  }
  for (final MapEntry(key: day, value: rows) in days.entries) {
    if (_daysBetween(previous, day) - 1 >= calendarQuietRun) {
      entries.add(AgendaGap(day));
    }
    entries.add(AgendaDay(day, rows));
    previous = day;
  }
  entries.add(const AgendaEnd());
  return entries;
}

/// Whole calendar days from [a] to [b], across a clock change.
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// The day [day] is in the strip and the agenda: `Today`, `Tomorrow`,
/// `Thu`.
String calendarDayName(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (_daysBetween(today, day)) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ => _weekdays[day.weekday - 1],
  };
}

/// The date beside a day's name: `Tue 29 Sep` beside `Today` and
/// `Tomorrow`, which say no weekday; `1 Oct` beside `Thu`, which does.
String calendarDayDate(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final gap = _daysBetween(today, day);
  return gap == 0 || gap == 1
      ? calendarShortDate(day)
      : '${day.day} ${_months[day.month - 1]}';
}

/// `Wed 21 Oct`.
String calendarShortDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

/// A day as a screen reader says it: `Today`, `Tomorrow`, `Friday 2
/// October`.
String spokenDay(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return switch (_daysBetween(today, day)) {
    0 => 'Today',
    1 => 'Tomorrow',
    _ =>
      '${_spokenWeekdays[day.weekday - 1]} ${day.day} '
          '${_spokenMonths[day.month - 1]}',
  };
}

/// The calendar's weeks, Monday to Sunday, from the one today is in to the
/// one the window ends in.
List<DateTime> calendarWeeks(CalendarWindow window) {
  final first = DateTime(
    window.start.year,
    window.start.month,
    window.start.day - (window.start.weekday - 1),
  );
  return [
    for (
      var monday = first;
      !monday.isAfter(window.end);
      monday = DateTime(monday.year, monday.month, monday.day + 7)
    )
      monday,
  ];
}

/// The seven days of the week that starts on [monday].
List<DateTime> calendarWeekDays(DateTime monday) => [
  for (var i = 0; i < 7; i++)
    DateTime(monday.year, monday.month, monday.day + i),
];

/// The tone and drawing of a day's dot: the most pressing of its rows (a
/// fault, then something on its way, then on the server, then the backlog),
/// hollow when nothing of the day has come yet. Null for a day with nothing.
({StatusTone tone, bool hollow})? calendarDayDot(List<CalendarEvent> events) {
  if (events.isEmpty) return null;
  int rank(StatusTone tone) => switch (tone) {
    StatusTone.error => 5,
    StatusTone.warning => 4,
    StatusTone.info => 3,
    StatusTone.success => 2,
    _ => 1,
  };
  var tone = events.first.state.tone;
  for (final event in events.skip(1)) {
    if (rank(event.state.tone) > rank(tone)) tone = event.state.tone;
  }
  return (tone: tone, hollow: events.every((e) => e.state.hollow));
}

/// The week's name over the strip: `This week`, `Next week`, `In 2 weeks`.
String calendarWeekName(int index) => switch (index) {
  0 => 'This week',
  1 => 'Next week',
  _ => 'In $index weeks',
};

/// `Mon 28 Sep – Sun 4 Oct`.
String calendarWeekRange(DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return '${calendarShortDate(monday)} – ${calendarShortDate(sunday)}';
}

/// The thing of [event] as one short line names it: `Sprite Fright, on
/// digital`; `Night Shift S2 E5 at 22:00`; `Sintel (Anniversary Edition),
/// album`.
String calendarEventShort(CalendarEvent event) => switch (event.kind) {
  CalendarKind.movie => [event.title, ?event.release].join(', '),
  CalendarKind.episode => [
    [event.title, ?event.code].join(' '),
    if (event.airsAt case final at?) 'at ${formatClockTime(at)}',
  ].join(' '),
  CalendarKind.album => '${event.title}, album',
  CalendarKind.book => '${event.title}, book',
};

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _spokenWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _spokenMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// What the band and the page's answer say of the calendar: the next
/// thing, and how much this week holds.
@immutable
class CalendarDigest {
  const CalendarDigest._({
    required this.lead,
    required this.today,
    required this.thisWeek,
    required this.otherDaysThisWeek,
    required this.now,
  });

  /// [events] sorted and inside the window, read at [now].
  factory CalendarDigest.of(List<CalendarEvent> events, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final sunday = DateTime(
      today.year,
      today.month,
      today.day + 7 - today.weekday,
    );
    final week = [
      for (final event in events)
        if (!event.day.isAfter(sunday) && !event.day.isBefore(today)) event,
    ];
    return CalendarDigest._(
      lead: events.firstOrNull,
      today: [
        for (final event in week)
          if (event.day == today) event,
      ],
      thisWeek: week.length,
      otherDaysThisWeek: {
        for (final event in week)
          if (event.day != today) event.day,
      }.length,
      now: now,
    );
  }

  /// The next thing, today's first when today has something.
  final CalendarEvent? lead;

  final List<CalendarEvent> today;

  /// How many things from today to Sunday.
  final int thisWeek;

  /// How many days of this week after today have something.
  final int otherDaysThisWeek;

  final DateTime now;

  /// The band's line, its first words bold: `Today` · `Sprite Fright · on
  /// digital`; `Nothing this week` · `Wed 21 Oct · Night Shift`; `Nothing of
  /// yours` · `in the next 30 days`.
  ({String lead, String rest}) bandLine() {
    final event = lead;
    if (event == null) {
      return (
        lead: 'Nothing of yours',
        rest: 'in the next ${CalendarWindow.days} days',
      );
    }
    if (thisWeek == 0) {
      return (
        lead: 'Nothing this week',
        rest: '· ${calendarShortDate(event.day)} · ${event.title}',
      );
    }
    return (
      lead: calendarDayName(event.day, now),
      rest: '· ${calendarBandWords(event)}',
    );
  }

  /// The band as one sentence, [silent] the kinds a quiet connection may be
  /// missing: `Calendar: today Sprite Fright, on digital, and 4 more days
  /// this week have something`.
  String spokenBand({Set<CalendarKind> silent = const {}}) {
    final event = lead;
    final String body;
    if (event == null) {
      body =
          'nothing of yours comes out in the next ${CalendarWindow.days} '
          'days. See what is coming out';
    } else if (thisWeek == 0) {
      body =
          'nothing this week. Next, ${spokenDay(event.day, now)}, '
          '${calendarEventShort(event)}';
    } else {
      final first = today.isNotEmpty
          ? 'today ${calendarEventShort(today.first)}'
          : 'next, ${spokenDay(event.day, now)}, ${calendarEventShort(event)}';
      final more = today.isNotEmpty ? otherDaysThisWeek : otherDaysThisWeek - 1;
      body = [
        first,
        if (more == 1) 'and 1 more day this week has something',
        if (more > 1) 'and $more more days this week have something',
      ].join(', ');
    }
    return [
      'Calendar: $body',
      if (silent.isNotEmpty)
        '${joinWithAnd([for (final kind in silent) kind.plural])} '
            'may be missing',
    ].join('. ');
  }

  /// The page's answer: the figure (an em dash when a quiet connection
  /// makes it unknowable), the sentence after it, and the next thing named
  /// bold. `6` · `things come out or air this week. Today:` · `Sprite
  /// Fright` · `, on digital.`
  ({String figure, String words, String? name, String tail}) answer({
    required bool countKnown,
  }) {
    final event = lead;
    if (event == null) {
      return (
        figure: '',
        words: 'Nothing of yours in the next ${CalendarWindow.days} days.',
        name: null,
        tail: '',
      );
    }
    final next = today.isNotEmpty ? today.first : event;
    final when = today.isNotEmpty
        ? 'Today:'
        : 'Next, ${calendarDayName(next.day, now) == 'Tomorrow' ? 'tomorrow' : calendarShortDate(next.day)}:';
    final rest = calendarAnswerTail(next);
    if (thisWeek == 0) {
      return (
        figure: '',
        words: 'Nothing this week. $when',
        name: next.title,
        tail: '$rest.',
      );
    }
    return (
      figure: countKnown ? '$thisWeek' : Lexicon.noFigure,
      words:
          '${thisWeek == 1 && countKnown ? 'thing comes out or airs' : 'things come out or air'} '
          'this week. $when',
      name: next.title,
      tail: '$rest.',
    );
  }
}

/// What follows a thing's name on the band: `on digital`, `S2 E5 at
/// 22:00`, `album`.
String calendarBandWords(CalendarEvent event) => switch (event.kind) {
  CalendarKind.movie => [event.title, ?event.release].join(' · '),
  CalendarKind.episode => [
    event.title,
    [
      ?event.code,
      if (event.airsAt case final at?) 'at ${formatClockTime(at)}',
    ].join(' '),
  ].where((part) => part.isNotEmpty).join(' · '),
  CalendarKind.album => '${event.title} · album',
  CalendarKind.book => '${event.title} · book',
};

/// What follows a thing's name in the page's answer: `, on digital`,
/// ` S2 E5 at 22:00`, `, album`.
String calendarAnswerTail(CalendarEvent event) => switch (event.kind) {
  CalendarKind.movie => event.release == null ? '' : ', ${event.release}',
  CalendarKind.episode => [
    if (event.code case final code?) ' $code',
    if (event.airsAt case final at?) ' at ${formatClockTime(at)}',
  ].join(),
  CalendarKind.album => ', album',
  CalendarKind.book => ', book',
};

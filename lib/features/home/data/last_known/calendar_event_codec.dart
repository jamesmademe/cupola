/// A calendar event as a last drawing keeps it: every field a row of Coming up
/// or Featured's "today" slide draws, nothing that runs.
///
///  * **Times are instants**: when an episode airs is an ISO instant, read
///    back on the device's clock; the day is the date itself, and an event
///    with a time takes its day from that time again, so a change of time zone
///    does not leave the two apart. What a row says (`Today`, `airs at 21:00`,
///    `not aired`) is made again against the time of the drawing.
///  * **Pictures keep no credential and no address** (`StoredImage`): a
///    picture on an arr's own server is kept by the connection the event was
///    read from (its target names it) and its path there, and is drawn at the
///    address that connection is reached at then, with its key; an event that
///    names no connection keeps only the pictures that carry no headers.
///  * **A download is a word, never a figure.** An event in the download queue
///    keeps the state it was in (`downloading`, `stuck`) and nothing that
///    counts or moves: no percentage, no time it would finish, no detail. It
///    is drawn as the stale queue row is, the state staying with its tone
///    drained to neutral: a fault or a download of a read that is old is not
///    news of today.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// [event] as JSON a last drawing can keep, with no credential in it: its
/// pictures kept by [keep].
Map<String, Object?> calendarEventToJson(
  CalendarEvent event,
  StoredImageKeeper keep,
) {
  final connection = _connectionOf(event);
  Map<String, Object?>? picture(ImageSource? source) {
    if (source == null) return null;
    return keep(
      source,
      service: connection?.service,
      connectionId: connection?.id,
    )?.toJson();
  }

  return {
    'identity': event.identity,
    'kind': event.kind.name,
    'day': _dateOf(event.day),
    'title': event.title,
    'airsAt': ?event.airsAt?.toUtc().toIso8601String(),
    'release': ?event.release,
    'season': ?event.season,
    'episode': ?event.episode,
    'lastEpisode': ?event.lastEpisode,
    'mark': ?event.mark?.name,
    'tmdbId': ?event.tmdbId,
    'byline': ?event.byline,
    'poster': ?picture(event.poster),
    'backdrop': ?picture(event.backdrop),
    'sources': event.sources,
    'note': ?event.note,
    'region': ?event.region,
    'target': ?_targetToJson(event.target),
    'state': _stateToJson(event.state),
  };
}

/// [json] read back, its pictures turned into what can be drawn by [image];
/// null for an event this version cannot read whole.
CalendarEvent? calendarEventFromJson(Object? json, StoredImageResolver image) {
  try {
    return _read(json, image);
  } catch (_) {
    // A record of another shape, or a picture that cannot be resolved:
    // nothing known, never half an event.
    return null;
  }
}

class _Unreadable implements Exception {
  const _Unreadable();
}

CalendarEvent _read(Object? json, StoredImageResolver image) {
  if (json is! Map) throw const _Unreadable();

  String text(String key) => switch (json[key]) {
    final String value when value.isNotEmpty => value,
    _ => throw const _Unreadable(),
  };
  String? maybeText(String key) => switch (json[key]) {
    null => null,
    final String value => value,
    _ => throw const _Unreadable(),
  };
  int? maybeNumber(String key) => switch (json[key]) {
    null => null,
    final int value => value,
    _ => throw const _Unreadable(),
  };
  T? maybeNamed<T extends Enum>(List<T> values, String key) =>
      switch (json[key]) {
        null => null,
        final String name => values.asNameMap()[name] ?? _unreadable(),
        _ => throw const _Unreadable(),
      };
  ImageSource? picture(String key) {
    if (json[key] == null) return null;
    final stored = StoredImage.fromJson(json[key]);
    if (stored == null) throw const _Unreadable();
    final source = image(stored);
    return source.url.isEmpty ? null : source;
  }

  final kind = maybeNamed(CalendarKind.values, 'kind') ?? _unreadable();
  final airsAt = switch (maybeText('airsAt')) {
    null => null,
    final raw => DateTime.tryParse(raw)?.toLocal() ?? _unreadable(),
  };
  final sources = switch (json['sources']) {
    final List<dynamic> list => [
      for (final source in list)
        if (source is String) source else throw const _Unreadable(),
    ],
    _ => throw const _Unreadable(),
  };
  return CalendarEvent(
    identity: text('identity'),
    kind: kind,
    day: airsAt == null
        ? _dateFrom(text('day'))
        : DateTime(airsAt.year, airsAt.month, airsAt.day),
    title: switch (json['title']) {
      final String title => title,
      _ => throw const _Unreadable(),
    },
    state: _stateFromJson(json['state']),
    airsAt: airsAt,
    release: maybeText('release'),
    season: maybeNumber('season'),
    episode: maybeNumber('episode'),
    lastEpisode: maybeNumber('lastEpisode'),
    mark: maybeNamed(CalendarMark.values, 'mark'),
    tmdbId: maybeNumber('tmdbId'),
    byline: maybeText('byline'),
    poster: picture('poster'),
    backdrop: picture('backdrop'),
    sources: sources,
    note: maybeText('note'),
    region: maybeText('region'),
    target: _targetFromJson(json['target']),
  );
}

Never _unreadable() => throw const _Unreadable();

/// The connection an event was read from, as far as it knows: what its
/// pictures' headers come from. A movie or a series names it in its target,
/// an album or a book too; a requester's event, read from no arr, names none.
({ServiceKey service, String id})? _connectionOf(CalendarEvent event) =>
    switch (event.target) {
      CalendarMediaTarget(:final connectionId?) when connectionId.isNotEmpty =>
        (service: event.kind.service, id: connectionId),
      CalendarShelfTarget(:final service, :final connectionId)
          when connectionId.isNotEmpty =>
        (service: service, id: connectionId),
      _ => null,
    };

/// `2026-10-12`: a calendar day, which is a date and not a moment.
String _dateOf(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _dateFrom(String date) {
  final parts = date.split('-');
  if (parts.length != 3) throw const _Unreadable();
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) throw const _Unreadable();
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    throw const _Unreadable();
  }
  return DateTime(year, month, day);
}

Map<String, Object?>? _targetToJson(CalendarTarget? target) => switch (target) {
  CalendarMediaTarget(:final key, :final connectionId) => {
    'kind': 'media',
    'media': switch (key) {
      MediaKey(tvdbId: != null) => 'tvdb',
      MediaKey(isMovie: true) => 'movie',
      _ => 'tv',
    },
    'id': key.tmdbId ?? key.tvdbId,
    'connection': ?connectionId,
  },
  CalendarShelfTarget(:final service, :final connectionId, :final id) => {
    'kind': 'shelf',
    'service': service.name,
    'connection': connectionId,
    'id': id,
  },
  null => null,
};

CalendarTarget? _targetFromJson(Object? json) {
  if (json == null) return null;
  if (json is! Map) throw const _Unreadable();
  final id = json['id'];
  if (id is! int) throw const _Unreadable();
  final connection = switch (json['connection']) {
    null => null,
    final String value => value,
    _ => throw const _Unreadable(),
  };
  switch (json['kind']) {
    case 'media':
      final media = json['media'];
      final key = switch (media) {
        'movie' || 'tv' => MediaKey.parse('$media', '$id'),
        'tvdb' => MediaKey.parse('tv', '$id', byTvdb: true),
        _ => null,
      };
      if (key == null) throw const _Unreadable();
      return CalendarMediaTarget(key, connectionId: connection);
    case 'shelf':
      final service = ServiceKey.values.asNameMap()[json['service']];
      if (service == null || connection == null || connection.isEmpty) {
        throw const _Unreadable();
      }
      return CalendarShelfTarget(service, connection, id);
  }
  throw const _Unreadable();
}

Map<String, Object?> _stateToJson(CalendarState state) {
  switch (state.stand) {
    case CalendarStand.notYet:
      return {'stand': 'notYet'};
    case CalendarStand.onServer:
      return {'stand': 'onServer'};
    case CalendarStand.out:
      return {'stand': 'out', 'missingKnown': state.missingKnown};
    case CalendarStand.inFlight:
      final queue = state.queue;
      final pipeline = queue?.pipeline;
      // A queue with no pipeline says nothing a drawing could keep: the
      // event reads as out, as it would without the queue's figures.
      if (queue == null || pipeline == null) {
        return {'stand': 'out', 'missingKnown': false};
      }
      return {
        'stand': 'inFlight',
        'pipeline': pipeline.name,
        'label': ?queue.labelOverride,
      };
  }
}

CalendarState _stateFromJson(Object? json) {
  if (json is! Map) throw const _Unreadable();
  switch (json['stand']) {
    case 'notYet':
      return const CalendarState.notYet();
    case 'onServer':
      return const CalendarState.onServer();
    case 'out':
      return switch (json['missingKnown']) {
        final bool known => CalendarState.out(missingKnown: known),
        _ => throw const _Unreadable(),
      };
    case 'inFlight':
      final pipeline = MediaPipeline.values.asNameMap()[json['pipeline']];
      final label = switch (json['label']) {
        null => null,
        final String value => value,
        _ => throw const _Unreadable(),
      };
      if (pipeline == null) throw const _Unreadable();
      // The state stays; the figure and the tone do not. A drawing that said
      // "stuck" in amber would be a fault of an old read drawn as today's, and
      // one that said "downloading" in blue, a transfer that may long be over.
      return CalendarState.inFlight(
        MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: pipeline,
          labelOverride: label,
          toneOverride: StatusTone.neutral,
        ),
      );
  }
  throw const _Unreadable();
}

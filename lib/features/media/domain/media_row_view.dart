import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// A row of "On your server" as it is drawn and spoken: who, what, and the
/// state's word in its tone.
@immutable
class MediaRowView {
  const MediaRowView({
    required this.name,
    required this.detail,
    required this.state,
    required this.tone,
    this.via,
    this.hollow = false,
    this.progress,
    this.action,
    this.dimmed = false,
    this.connectionId,
  });

  /// The connection's name: `Radarr`, `Radarr · 4K`.
  final String name;

  /// How the fact reached the app, when it is another service's claim:
  /// `through Seerr` (case b).
  final String? via;

  /// What the source holds: `1080p Bluray · 1.2 GB`, `Anna · Sat 12 Sep`.
  final String detail;

  /// The state's one word: `Available`, `Did not answer`, `DE wanted`.
  final String state;

  final StatusTone tone;

  /// The backlog's ring rather than a filled dot: a neutral state.
  final bool hollow;

  /// How far a download is, 0..1, drawn under the row.
  final double? progress;

  /// The one quiet way forward the row offers: `Set up Seerr`, `Retry`,
  /// `Add Radarr · 4K to Cupola`.
  final String? action;

  /// Case a: the row is dimmed, and still opens the setup form.
  final bool dimmed;

  /// The connection the row reads, for its tap and for the page's focus.
  final String? connectionId;

  /// The one sentence a screen reader speaks for the row.
  String get spoken =>
      [name, ?via, if (detail.isNotEmpty) detail, state, ?action].join('. ');
}

/// [row] in the page's words, or null where the row draws nothing: Bazarr
/// answering that it follows no copy of the title.
///
/// [title] names a connection the way the rest of the app does
/// (`SettingsModel.connectionTitle`); [now] is the clock the request dates
/// are read against.
MediaRowView? mediaRowView(
  MediaRow row, {
  required String Function(ServiceInstance connection) title,
  required DateTime now,
}) {
  return switch (row) {
    MediaNotSetUpRow(:final service) => MediaRowView(
      name: service.title,
      detail: _whatItBrings(service),
      state: StateWord.notSetUp.label,
      tone: StatusTone.neutral,
      hollow: true,
      action: Lexicon.setUp(service.title),
      dimmed: true,
    ),
    MediaThroughSeerrRow(:final copy, :final mediaInfo) => () {
      final status = seerrMediaStatus(mediaInfo, is4k: copy.copy.is4k);
      final name = copy.serverName(
        connectionTitle: (connection) => title(connection),
      );
      return MediaRowView(
        name: name,
        via: 'through Seerr',
        detail: '',
        state: status.label,
        tone: status.tone,
        hollow: status.tone == StatusTone.neutral,
        action: 'Add $name to Cupola',
      );
    }(),
    MediaConnectionRow(:final connection, :final reading) => _connectionView(
      connection,
      reading,
      name: title(connection),
      now: now,
    ),
  };
}

/// What a service that is not set up would bring to the page, for its
/// dimmed row.
String _whatItBrings(ServiceKey service) => switch (service) {
  ServiceKey.seerr => 'Requests, cast and trailers need it',
  ServiceKey.radarr => 'Files and searches need it',
  ServiceKey.sonarr => 'Episodes and searches need it',
  _ => '',
};

MediaRowView? _connectionView(
  ServiceInstance connection,
  MediaReading<Object?> reading, {
  required String name,
  required DateTime now,
}) {
  switch (reading) {
    case MediaReadingWaiting():
      return MediaRowView(
        name: name,
        detail: '',
        state: '',
        tone: StatusTone.neutral,
        connectionId: connection.id,
      );
    case MediaReadingFailed(:final failure, :final gateway, :final lastKnown):
      final known = lastKnown == null
          ? null
          : _answeredView(connection, lastKnown.value, name: name, now: now);
      final since = lastKnown == null
          ? ''
          : ' since ${formatClockTime(lastKnown.at)}';
      return MediaRowView(
        name: name,
        detail: known == null
            ? ''
            : 'Last known: ${[if (known.detail.isNotEmpty) known.detail, known.state].join(' · ')}',
        state: '${failureLabel(failure, gateway: gateway)}$since',
        tone: failureTone(failure),
        action: Lexicon.retry,
        connectionId: connection.id,
      );
    case MediaReadingAnswered(:final answer):
      return _answeredView(connection, answer.value, name: name, now: now);
  }
}

MediaRowView? _answeredView(
  ServiceInstance connection,
  Object? value, {
  required String name,
  required DateTime now,
}) {
  MediaRowView view({
    required String detail,
    required String state,
    required StatusTone tone,
    double? progress,
  }) => MediaRowView(
    name: name,
    detail: detail,
    state: state,
    tone: tone,
    hollow: tone == StatusTone.neutral,
    progress: progress,
    connectionId: connection.id,
  );

  switch (value) {
    case MediaStreamCopy(:final outcome, :final item):
      if (outcome != StreamLookupOutcome.found || item == null) {
        return view(
          detail: 'Not in any library',
          state: 'Not there',
          tone: StatusTone.neutral,
        );
      }
      final left = item.isInProgress && item.runtimeMs != null
          ? '${formatRuntimeMinutes(((item.runtimeMs! - (item.resumeOffsetMs ?? 0)) / 60000).ceil())} left'
          : null;
      return view(
        detail: item.isPlayed ? 'Watched' : left ?? '',
        state: _onDisk.label,
        tone: _onDisk.tone,
      );
    case MediaRadarrCopy(:final movie, :final status):
      if (movie == null || status == null) {
        return view(
          detail: '',
          state: 'Not added yet',
          tone: StatusTone.neutral,
        );
      }
      final file = movie.movieFile;
      return view(
        detail: [
          if (file?.qualityName case final quality? when quality.isNotEmpty)
            qualityWords(quality),
          if (file?.size case final size? when size > 0) formatBytes(size),
        ].join(' · '),
        state: status.label,
        tone: status.tone,
        progress: status.progress,
      );
    case MediaSonarrCopy(:final series, :final status):
      if (series == null || status == null) {
        return view(
          detail: '',
          state: 'Not added yet',
          tone: StatusTone.neutral,
        );
      }
      final files = intOrNull(series.statistics?['episodeFileCount']);
      final episodes = intOrNull(series.statistics?['episodeCount']);
      return view(
        detail: files == null || episodes == null
            ? ''
            : '$files of $episodes episodes',
        state: status.label,
        tone: status.tone,
        progress: status.progress,
      );
    case MediaBazarrCopy(:final movie?):
      return view(
        detail: _languageCodes(movie.presentLanguages),
        state: movie.missingLanguages.isEmpty
            ? 'Nothing wanted'
            : '${_languageCodes(movie.missingLanguages)} wanted',
        tone: StatusTone.neutral,
      );
    case MediaBazarrCopy(:final series?):
      final missing = series.episodeMissingCount ?? 0;
      return view(
        detail: '',
        state: missing == 0
            ? 'Nothing wanted'
            : '${countLabel(missing, 'episode')} wanted',
        tone: StatusTone.neutral,
      );
    case MediaBazarrCopy() || null:
      return null;
    case final MediaSeerrRecord record:
      final status = seerrMediaStatus(record.mediaInfo);
      final request = _latestRequest(record.mediaInfo);
      return view(
        // "Nobody" only where Seerr has no record at all: a record without
        // its request list still means somebody asked.
        detail: request == null
            ? (record.mediaInfo == null ? 'Nobody has asked for it' : '')
            : [
                if (request.who.isNotEmpty) request.who,
                if (request.when.isNotEmpty)
                  formatShortDate(request.when, now: now),
              ].join(' · '),
        state: status.label,
        tone: status.tone,
      );
  }
  return null;
}

/// A copy a viewer can play: the badge's own word and tone.
const _onDisk = MediaStatusInfo(availability: MediaAvailability.available);

/// Subtitle languages by their two-letter code, upper case, each once:
/// `EN · IT`.
String _languageCodes(List<BazarrSubtitleLanguage> languages) => languages
    .map((language) => (language.code2 ?? language.name ?? '').toUpperCase())
    .where((code) => code.isNotEmpty)
    .toSet()
    .join(' · ');

/// The most recent request in Seerr's [mediaInfo]: who asked, and when.
({String who, String when})? _latestRequest(Map<String, dynamic>? mediaInfo) {
  final requests = mediaInfo?['requests'];
  if (requests is! List || requests.isEmpty) return null;
  final latest = requests.whereType<Map>().reduce(
    (a, b) =>
        '${a['createdAt'] ?? ''}'.compareTo('${b['createdAt'] ?? ''}') >= 0
        ? a
        : b,
  );
  final by = mapOrNull(latest['requestedBy']);
  return (
    who: '${by?['displayName'] ?? by?['username'] ?? ''}',
    when: '${latest['createdAt'] ?? ''}',
  );
}

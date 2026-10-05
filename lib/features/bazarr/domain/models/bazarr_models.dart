import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/status/media_status.dart';

class BazarrSubtitleLanguage {
  final String? name;
  final String? code2;
  final String? code3;
  final bool forced;
  final bool hi;

  const BazarrSubtitleLanguage({
    this.name,
    this.code2,
    this.code3,
    this.forced = false,
    this.hi = false,
  });

  factory BazarrSubtitleLanguage.fromJson(Map<String, dynamic> json) {
    return BazarrSubtitleLanguage(
      name: stringOrNull(json['name']),
      code2: stringOrNull(json['code2']),
      code3: stringOrNull(json['code3']),
      forced: json['forced'] == true,
      hi: json['hi'] == true,
    );
  }
}

List<BazarrSubtitleLanguage> parseBazarrSubtitleLanguages(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(stringKeyMap)
        .map(BazarrSubtitleLanguage.fromJson)
        .toList(growable: false);
  }
  return const <BazarrSubtitleLanguage>[];
}

/// The subtitle languages a title already has, from the `subtitles` list
/// Bazarr's `postprocess` attaches to every movie and episode record (it looks
/// them up by `radarrId` / `sonarrEpisodeId`, so wanted records carry it too).
///
/// One entry per language and flavour: Bazarr lists one row per *file*, so an
/// embedded English track and an external `.en.srt` are two rows that say one
/// thing — English is there.
List<BazarrSubtitleLanguage> parseBazarrPresentSubtitles(dynamic value) {
  final seen = <String>{};
  return [
    for (final language in parseBazarrSubtitleLanguages(value))
      if (seen.add(
        '${language.code2 ?? language.name}:${language.forced}:${language.hi}',
      ))
        language,
  ];
}

class BazarrSeries {
  final int sonarrSeriesId;
  final String? title;
  final String? sortTitle;
  final int? year;
  final String? path;
  final bool monitored;
  final int? episodeMissingCount;
  final int? episodeCount;
  final int? profileId;
  final List<String> tags;

  const BazarrSeries({
    required this.sonarrSeriesId,
    this.title,
    this.sortTitle,
    this.year,
    this.path,
    required this.monitored,
    this.episodeMissingCount,
    this.episodeCount,
    this.profileId,
    this.tags = const [],
  });

  factory BazarrSeries.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrSeries(
      sonarrSeriesId: intOrNull(json['sonarrSeriesId']) ?? 0,
      title: stringOrNull(json['title']),
      sortTitle: stringOrNull(json['sortTitle']),
      year: intOrNull(json['year']),
      path: stringOrNull(json['path']),
      monitored: json['monitored'] == true,
      episodeMissingCount: intOrNull(json['episodeMissingCount']),
      episodeCount: intOrNull(json['episodeFileCount']),
      profileId: intOrNull(json['profileId']),
      tags: tags,
    );
  }
}

class BazarrMovie {
  final int radarrId;
  final String? title;
  final String? sortTitle;
  final int? year;
  final String? path;
  final bool monitored;
  final List<BazarrSubtitleLanguage> missingLanguages;

  /// The languages already on disk — see [parseBazarrPresentSubtitles].
  final List<BazarrSubtitleLanguage> presentLanguages;
  final int? profileId;
  final List<String> tags;

  const BazarrMovie({
    required this.radarrId,
    this.title,
    this.sortTitle,
    this.year,
    this.path,
    required this.monitored,
    this.missingLanguages = const [],
    this.presentLanguages = const [],
    this.profileId,
    this.tags = const [],
  });

  int get missingSubtitlesCount => missingLanguages.length;

  factory BazarrMovie.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrMovie(
      radarrId: intOrNull(json['radarrId']) ?? 0,
      title: stringOrNull(json['title']),
      sortTitle: stringOrNull(json['sortTitle']),
      year: intOrNull(json['year']),
      path: stringOrNull(json['path']),
      monitored: json['monitored'] == true,
      missingLanguages: parseBazarrSubtitleLanguages(json['missing_subtitles']),
      presentLanguages: parseBazarrPresentSubtitles(json['subtitles']),
      profileId: intOrNull(json['profileId']),
      tags: tags,
    );
  }
}

/// One episode Bazarr follows (`/api/episodes`): the subtitle languages it
/// has on disk, and the ones it is still looking for.
class BazarrEpisode {
  final int sonarrEpisodeId;
  final int season;
  final int episode;
  final String? title;

  /// The languages already on disk — see [parseBazarrPresentSubtitles].
  final List<BazarrSubtitleLanguage> presentLanguages;
  final List<BazarrSubtitleLanguage> missingLanguages;

  const BazarrEpisode({
    required this.sonarrEpisodeId,
    required this.season,
    required this.episode,
    this.title,
    this.presentLanguages = const [],
    this.missingLanguages = const [],
  });

  factory BazarrEpisode.fromJson(Map<String, dynamic> json) => BazarrEpisode(
    sonarrEpisodeId: intOrNull(json['sonarrEpisodeId']) ?? 0,
    season: intOrNull(json['season']) ?? 0,
    episode: intOrNull(json['episode']) ?? 0,
    title: stringOrNull(json['title']),
    presentLanguages: parseBazarrPresentSubtitles(json['subtitles']),
    missingLanguages: parseBazarrSubtitleLanguages(json['missing_subtitles']),
  );
}

class BazarrWantedItem {
  final String? title;
  final String? seriesTitle;
  final String? episodeNumber;
  final String? episodeTitle;
  final int? season;
  final List<BazarrSubtitleLanguage> missingLanguages;

  /// The languages already on disk — see [parseBazarrPresentSubtitles].
  final List<BazarrSubtitleLanguage> presentLanguages;
  final int? sonarrSeriesId;
  final int? sonarrEpisodeId;
  final int? radarrId;
  final String? sceneName;
  final List<String> tags;

  const BazarrWantedItem({
    this.title,
    this.seriesTitle,
    this.episodeNumber,
    this.episodeTitle,
    this.season,
    this.missingLanguages = const [],
    this.presentLanguages = const [],
    this.sonarrSeriesId,
    this.sonarrEpisodeId,
    this.radarrId,
    this.sceneName,
    this.tags = const [],
  });

  int get missingSubtitlesCount => missingLanguages.length;

  /// The episode in the app's one spelling, `S2 E4`.
  ///
  /// Bazarr formats [episodeNumber] itself, `2x4` (or `S02E04` on some
  /// builds), and printed as it arrived it was a second spelling beside every
  /// Sonarr row. Read back into its numbers and spelled by the shared
  /// formatter; the string Bazarr sent when it is neither shape.
  String? get episodeCode {
    final parsed = _parseEpisodeNumber(episodeNumber);
    if (parsed == null) return episodeNumber;
    return formatEpisodeCode(parsed.season, parsed.episode);
  }

  /// What [episodeCode] is, in words: `Season 2, episode 4`. A code reads as
  /// letters and digits otherwise.
  String? get spokenEpisode {
    final parsed = _parseEpisodeNumber(episodeNumber);
    if (parsed == null) {
      return episodeNumber == null ? null : 'Episode $episodeNumber';
    }
    return 'Season ${parsed.season}, episode ${parsed.episode}';
  }

  factory BazarrWantedItem.fromJson(Map<String, dynamic> json) {
    final seasonRaw = intOrNull(json['season']);
    final episodeNumberRaw = stringOrNull(json['episode_number']);
    final seasonFromEpisode =
        seasonRaw ?? _seasonFromEpisodeCode(episodeNumberRaw);

    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((e) => stringOrNull(e))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    return BazarrWantedItem(
      title: stringOrNull(json['title']),
      seriesTitle: stringOrNull(json['seriesTitle']),
      episodeNumber: episodeNumberRaw,
      episodeTitle: stringOrNull(json['episodeTitle']),
      season: seasonFromEpisode,
      missingLanguages: parseBazarrSubtitleLanguages(json['missing_subtitles']),
      presentLanguages: parseBazarrPresentSubtitles(json['subtitles']),
      sonarrSeriesId: intOrNull(json['sonarrSeriesId']),
      sonarrEpisodeId: intOrNull(json['sonarrEpisodeId']),
      radarrId: intOrNull(json['radarrId']),
      sceneName: stringOrNull(json['sceneName']),
      tags: tags,
    );
  }

  static int? _seasonFromEpisodeCode(String? value) =>
      _parseEpisodeNumber(value)?.season;

  /// `2x4`, `2x04` or `S02E04`, as Bazarr may write them.
  static final _episodeNumberShape = RegExp(
    r'^\s*[Ss]?(\d+)\s*[xXeE]\s*(\d+)\s*$',
  );

  static ({int season, int episode})? _parseEpisodeNumber(String? value) {
    final match = _episodeNumberShape.firstMatch(value ?? '');
    if (match == null) return null;
    return (
      season: int.parse(match.group(1)!),
      episode: int.parse(match.group(2)!),
    );
  }
}

class BazarrBadges {
  final int episodes;
  final int movies;
  final int providers;
  final bool status;
  final bool sonarrSignalR;
  final bool radarrSignalR;
  final int announcements;

  const BazarrBadges({
    required this.episodes,
    required this.movies,
    required this.providers,
    required this.status,
    required this.sonarrSignalR,
    required this.radarrSignalR,
    required this.announcements,
  });

  int get totalWanted => episodes + movies;

  factory BazarrBadges.fromJson(Map<String, dynamic> json) {
    return BazarrBadges(
      episodes: intOrNull(json['episodes']) ?? 0,
      movies: intOrNull(json['movies']) ?? 0,
      providers: intOrNull(json['providers']) ?? 0,
      status: json['status'] == true,
      sonarrSignalR: json['sonarr_signalr'] == true,
      radarrSignalR: json['radarr_signalr'] == true,
      announcements: intOrNull(json['announcements']) ?? 0,
    );
  }
}

/// The provider data Bazarr exposes through its supported badges endpoint.
///
/// Bazarr's local API contract does not expose provider names, quotas, or
/// throttle windows. Keep this model deliberately aggregate-only so the UI
/// cannot accidentally manufacture a provider table from unrelated fields.
class BazarrProviderSummary {
  final int? configuredCount;

  const BazarrProviderSummary({this.configuredCount});

  factory BazarrProviderSummary.fromJson(Map<String, dynamic> json) {
    return BazarrProviderSummary(configuredCount: intOrNull(json['providers']));
  }
}

/// A provider currently returned by Bazarr's provider-status endpoint.
///
/// Bazarr returns throttled providers by default, rather than a complete
/// configured-provider registry. Missing fields therefore stay nullable and
/// the UI must not turn the response into a fabricated healthy list.
class BazarrProviderStatus {
  final String? name;
  final String? status;
  final String? retry;

  const BazarrProviderStatus({this.name, this.status, this.retry});

  factory BazarrProviderStatus.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return BazarrProviderStatus(
      name: stringOrNull(json['name']),
      status: stringOrNull(json['status']),
      retry: stringOrNull(json['retry']),
    );
  }

  StatusTone get tone => switch (status?.trim().toLowerCase()) {
    null || '' => StatusTone.neutral,
    'good' => StatusTone.success,
    'history' => StatusTone.neutral,
    _ => StatusTone.warning,
  };

  String get displayName =>
      name?.trim().isNotEmpty == true ? name!.trim() : 'Unnamed provider';

  String get statusLabel =>
      status?.trim().isNotEmpty == true ? status!.trim() : '—';

  String get retryLabel {
    final value = retry?.trim();
    return value == null || value.isEmpty || value == '-' ? '—' : value;
  }
}

/// Bazarr's integer action codes for `TableHistory.action` /
/// `TableHistoryMovie.action` columns.
class BazarrHistoryActionCode {
  BazarrHistoryActionCode._();
  static const downloaded = 1;
  static const upgraded = 2;
  static const removed = 3;
}

enum BazarrHistoryAction {
  downloaded,
  upgraded,
  matched,
  failed,
  removed,
  unknown,
}

extension BazarrHistoryActionX on BazarrHistoryAction {
  String get label {
    return switch (this) {
      BazarrHistoryAction.downloaded => 'DOWNLOADED',
      BazarrHistoryAction.upgraded => 'UPGRADED',
      BazarrHistoryAction.matched => 'MATCHED',
      BazarrHistoryAction.failed => 'FAILED',
      BazarrHistoryAction.removed => 'REMOVED',
      BazarrHistoryAction.unknown => 'EVENT',
    };
  }

  /// Maps a Bazarr history action integer (1=downloaded, 2=upgraded,
  /// 3=removed) plus well-known string fallbacks for legacy payloads.
  static BazarrHistoryAction fromActionCode(dynamic raw) {
    if (raw is num) {
      switch (raw.toInt()) {
        case BazarrHistoryActionCode.downloaded:
          return BazarrHistoryAction.downloaded;
        case BazarrHistoryActionCode.upgraded:
          return BazarrHistoryAction.upgraded;
        case BazarrHistoryActionCode.removed:
          return BazarrHistoryAction.removed;
      }
    }
    if (raw is String) {
      switch (raw.toLowerCase()) {
        case 'downloaded':
        case 'download':
          return BazarrHistoryAction.downloaded;
        case 'upgraded':
        case 'upgrade':
          return BazarrHistoryAction.upgraded;
        case 'matched':
        case 'match':
        case 'synced':
          return BazarrHistoryAction.matched;
        case 'failed':
        case 'failure':
          return BazarrHistoryAction.failed;
        case 'removed':
        case 'removed_subtitle':
          return BazarrHistoryAction.removed;
      }
    }
    return BazarrHistoryAction.unknown;
  }
}

enum BazarrHistoryKind { episode, movie }

/// Lightweight typed view of recent Bazarr history used by the dashboard.
///
/// Bazarr returns untyped maps for `/api/episodes/history` and
/// `/api/movies/history`. The endpoints expose:
/// - `action` as an integer (1=downloaded, 2=upgraded, 3=removed)
/// - `language` as a nested object `{name, code2, code3, forced, hi}`
///   after `postprocess()` runs
/// - `timestamp` as a `pretty.date()` human-readable string and
///   `parsed_timestamp` as the underlying `strftime('%x %X')` value.
/// The helpers below extract the fields the dashboard actually displays.
class BazarrHistoryItem {
  final BazarrHistoryKind kind;
  final String? title;
  final String? subtitle;
  final String? languageLabel;
  final String? provider;
  final int? actionCode;
  final String? timestamp;
  final String? parsedTimestamp;
  final int? score;
  final bool upgradable;
  final bool blacklisted;

  const BazarrHistoryItem({
    required this.kind,
    this.title,
    this.subtitle,
    this.languageLabel,
    this.provider,
    this.actionCode,
    this.timestamp,
    this.parsedTimestamp,
    this.score,
    this.upgradable = false,
    this.blacklisted = false,
  });

  BazarrHistoryAction get action =>
      BazarrHistoryActionX.fromActionCode(actionCode);

  factory BazarrHistoryItem.fromEpisodeMap(Map<String, dynamic> json) {
    return BazarrHistoryItem(
      kind: BazarrHistoryKind.episode,
      title: stringOrNull(json['seriesTitle']) ?? stringOrNull(json['title']),
      subtitle: stringOrNull(json['episodeTitle']),
      languageLabel: _languageLabel(json['language']),
      provider: stringOrNull(json['provider']),
      actionCode: intOrNull(json['action']),
      timestamp: stringOrNull(json['timestamp']),
      parsedTimestamp: stringOrNull(json['parsed_timestamp']),
      score: intOrNull(json['score']),
      upgradable: json['upgradable'] == true,
      blacklisted: json['blacklisted'] == true,
    );
  }

  factory BazarrHistoryItem.fromMovieMap(Map<String, dynamic> json) {
    return BazarrHistoryItem(
      kind: BazarrHistoryKind.movie,
      title: stringOrNull(json['title']),
      subtitle: stringOrNull(json['description']),
      languageLabel: _languageLabel(json['language']),
      provider: stringOrNull(json['provider']),
      actionCode: intOrNull(json['action']),
      timestamp: stringOrNull(json['timestamp']),
      parsedTimestamp: stringOrNull(json['parsed_timestamp']),
      score: intOrNull(json['score']),
      upgradable: json['upgradable'] == true,
      blacklisted: json['blacklisted'] == true,
    );
  }

  /// `language` may be a Bazarr `subtitles_language_model` object (after
  /// `postprocess`) or a raw language string. We extract a short display
  /// label (code2 or name).
  static String? _languageLabel(dynamic value) {
    if (value is Map) {
      final typed = stringKeyMap(value);
      return stringOrNull(typed['code2']) ?? stringOrNull(typed['name']);
    }
    return stringOrNull(value);
  }
}

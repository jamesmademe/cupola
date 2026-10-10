/// The downloads an arr finished and would not import: why, how the Review
/// sorts their files, and the words before and after the import.
library;

import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One download the arr finished and would not import, as its queue reads it.
class BlockedDownload {
  const BlockedDownload({
    required this.downloadId,
    required this.title,
    this.mediaId,
    this.message,
  });

  /// The download client's id for it, which the arr reads its files by.
  final String downloadId;

  final String title;

  /// The library item the arr grabbed it for: the series, movie or artist.
  final int? mediaId;

  /// What the arr says about it, word for word.
  final String? message;
}

/// A Review of the downloads one arr's connection finished and would not
/// import, as it was read.
class BlockedImportReview {
  const BlockedImportReview({
    this.downloads = const [],
    this.needYouPaths = const [],
    this.needYouKinds = const {},
    this.leftOut = 0,
    this.unread = 0,
    this.replacing = const {},
  });

  /// The blocked downloads, in the queue's order.
  final List<BlockedDownload> downloads;

  /// The files that needed the user when they were read, in their order. A
  /// file keeps its place among them once the user has placed it.
  final List<String> needYouPaths;

  /// By path, what each of them needed when read: a file the user placed
  /// keeps the question it was asked.
  final Map<String, NeedYouKind> needYouKinds;

  /// Samples and files of a kind the arr does not import: they stay where
  /// they are.
  final int leftOut;

  /// Downloads whose files the arr would not list.
  final int unread;

  /// By path, the quality of the library file each file replaces
  /// (`HDTV-720p`).
  final Map<String, String> replacing;
}

/// Why the arr stopped, read from its own message.
enum BlockedImportCause {
  /// The arr knows the title from its grab, but the names do not say it
  /// (`…matched to series by ID. Automatic import is not possible.`).
  namesDontMatch,

  /// The file is no better than the one the library has.
  notAnUpgrade,

  /// The names do not say what the files are.
  unrecognised,

  /// The download holds fewer files than the arr expected.
  incomplete,

  /// A message the app has no words for: it is shown as the arr wrote it.
  unknown,
}

final _causes = <(RegExp, BlockedImportCause)>[
  (
    RegExp(
      r'matched to (series|movie|artist|author) by id|title mismatch|'
      r'was unexpected considering',
      caseSensitive: false,
    ),
    BlockedImportCause.namesDontMatch,
  ),
  (
    RegExp(r'not (a|an) (custom format )?upgrade', caseSensitive: false),
    BlockedImportCause.notAnUpgrade,
  ),
  (
    RegExp(
      r'unable to (parse|identify|determine)|unknown (series|movie|artist)|'
      r'invalid season or episode',
      caseSensitive: false,
    ),
    BlockedImportCause.unrecognised,
  ),
  (
    RegExp(
      r'not imported or missing|no files found are eligible|'
      r'missing from the release',
      caseSensitive: false,
    ),
    BlockedImportCause.incomplete,
  ),
];

/// The first cause the app recognises among [messages], in their order.
BlockedImportCause blockedImportCauseOf(Iterable<String?> messages) {
  for (final message in messages) {
    if (message == null) continue;
    for (final (pattern, cause) in _causes) {
      if (pattern.hasMatch(message)) return cause;
    }
  }
  return BlockedImportCause.unknown;
}

/// [messages] once each, in their order: eighteen downloads stopped for one
/// reason say it once.
List<String> distinctMessages(Iterable<String?> messages) {
  final seen = <String>{};
  return [
    for (final message in messages)
      if (message != null &&
          message.trim().isNotEmpty &&
          seen.add(message.trim()))
        message.trim(),
  ];
}

/// `Review 18 imports`: one import per file.
String blockedImportTitle(int files) =>
    files == 1 ? 'Review the import' : 'Review $files imports';

/// What the arr calls the title it grabbed, in a sentence.
String _titleNoun(ServiceKey service) => switch (service) {
  ServiceKey.radarr => "movie's name",
  ServiceKey.lidarr => "artist's name",
  _ => 'series name',
};

/// What one file is, to the arr.
String _unit(ServiceKey service) => switch (service) {
  ServiceKey.radarr => 'movie',
  ServiceKey.lidarr => 'track',
  _ => 'episode',
};

/// The sentence under the title: why the arr stopped, simply.
String blockedImportExplanation(
  ServiceKey service,
  BlockedImportCause cause, {
  required bool one,
}) {
  final arr = service.title;
  return switch (cause) {
    BlockedImportCause.namesDontMatch =>
      one
          ? "The file name doesn't match the ${_titleNoun(service)}, so $arr "
                "won't guess."
          : "The file names don't match the ${_titleNoun(service)}, so $arr "
                "won't guess.",
    BlockedImportCause.notAnUpgrade =>
      one
          ? "It's no better than the file $arr already has, so $arr won't "
                'replace it.'
          : "They're no better than the files $arr already has, so $arr "
                "won't replace them.",
    BlockedImportCause.unrecognised =>
      one
          ? "$arr can't tell what this file is from its name."
          : "$arr can't tell what these files are from their names.",
    BlockedImportCause.incomplete =>
      "Some files $arr expected aren't in the download.",
    BlockedImportCause.unknown =>
      one
          ? "$arr finished it and won't import it on its own."
          : "$arr finished them and won't import them on its own.",
  };
}

/// `In plain words`, under what the arr says: the cause for someone who
/// never read the arr's FAQ, and how many files say what they are. Null for a
/// message the app has no words for.
///
/// [title] is the one title every file was grabbed for, when they share one;
/// [unnamed] is how many of the [total] files do not say which one they are.
String? blockedImportPlainWords(
  ServiceKey service,
  BlockedImportCause cause, {
  String? title,
  required int total,
  required int unnamed,
}) {
  final arr = service.title;
  final unit = _unit(service);
  final named = total - unnamed;
  final counted = total == 1
      ? (unnamed == 0
            ? 'Its name says which $unit it is.'
            : "Its name doesn't say which $unit it is.")
      : unnamed == 0
      ? 'All $total name their $unit clearly.'
      : named == 0
      ? 'None of the $total names its $unit.'
      : '$named name their $unit clearly; $unnamed '
            "${unnamed == 1 ? "doesn't" : "don't"}.";
  return switch (cause) {
    BlockedImportCause.namesDontMatch => [
      if (title != null)
        total == 1
            ? "$arr grabbed it for $title, but its name doesn't say so."
            : "$arr grabbed these for $title, but their names don't say so.",
      counted,
    ].join(' '),
    BlockedImportCause.unrecognised => [
      "$arr reads a file's name to know what it is.",
      counted,
    ].join(' '),
    BlockedImportCause.notAnUpgrade =>
      '$arr keeps the file it has unless the new one is better. Importing '
          '${total == 1 ? 'this one' : 'these'} replaces it anyway.',
    BlockedImportCause.incomplete => 'The files that are here can still go in.',
    BlockedImportCause.unknown => null,
  };
}

/// What a file the user has to look at is missing.
enum NeedYouKind {
  /// Sonarr knows the series but not the episode: the season and episode
  /// are picked on the row.
  episode,

  /// The arr does not know what the file is: the title is chosen in the
  /// match sheet.
  identity,

  /// Everything is known, and the arr refused it anyway (not an upgrade, a
  /// file it would not take): it goes in only when the user says so.
  refused,
}

/// Which choice [item] needs.
NeedYouKind needYouKindOf(ServiceKey service, ManualImportItem item) {
  if (!item.hasBlockingRequirementsFor(service)) return NeedYouKind.refused;
  if (service == ServiceKey.sonarr &&
      (intOrNull(item.series?['id']) ?? 0) > 0) {
    return NeedYouKind.episode;
  }
  return NeedYouKind.identity;
}

/// The files of a Review, sorted once when they are read: those that can go
/// in as they are, those that need the user, and how many stay where they are
/// (samples and files of a kind the arr does not import).
typedef BlockedImportSplit = ({
  List<ManualImportItem> clear,
  List<ManualImportItem> needYou,
  int leftOut,
});

/// Sorts [items] for the Review. A file is clear only when the arr would
/// take it as it is: matched whole and refused for nothing. A file the arr
/// refused (not an upgrade) needs the user even when matched, since
/// importing it replaces a file in the library.
BlockedImportSplit splitBlockedImport(
  ServiceKey service,
  Iterable<ManualImportItem> items,
) {
  final clear = <ManualImportItem>[];
  final needYou = <ManualImportItem>[];
  var leftOut = 0;
  for (final item in items) {
    if (!manualImportIsSupportedFile(service, item) ||
        item.isSample ||
        item.isAlreadyImported) {
      leftOut++;
    } else if (item.isReadyForImportFor(service) &&
        !item.rejections.any((rejection) => rejection.isPermanent)) {
      clear.add(item);
    } else {
      needYou.add(item);
    }
  }
  return (clear: clear, needYou: needYou, leftOut: leftOut);
}

/// The explanation under `6 need you`: what each row asks for.
String needYouExplanation(
  ServiceKey service,
  Iterable<NeedYouKind> kinds, {
  required bool one,
}) {
  final arr = service.title;
  final distinct = kinds.toSet();
  if (distinct.length != 1) return 'Each needs a choice before it can go in.';
  return switch (distinct.single) {
    NeedYouKind.episode =>
      one
          ? "$arr can't tell which episode this is. Pick the season and "
                'episode.'
          : "$arr can't tell which episode these are. Pick the season and "
                'episode for each.',
    NeedYouKind.identity =>
      one
          ? "$arr can't tell what this is. Pick the ${_unitTitle(service)}."
          : "$arr can't tell what these are. Pick the ${_unitTitle(service)} "
                'for each.',
    NeedYouKind.refused =>
      one
          ? '$arr refused it. It goes in only if you add it.'
          : '$arr refused these. Each goes in only if you add it.',
  };
}

String _unitTitle(ServiceKey service) => switch (service) {
  ServiceKey.radarr => 'movie',
  ServiceKey.lidarr => 'album',
  _ => 'series',
};

/// The episode number a file's name carries without its season
/// (`Laundromat.Tapes.E03.720p` is 3), to start the picker on.
int? episodeNumberInName(String name) {
  final match = RegExp(
    r'(?:^|[^a-z0-9])(?:e|ep|episode)[ ._-]?(\d{1,3})(?![0-9])',
    caseSensitive: false,
  ).firstMatch(name);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// A series' seasons as its payload lists them, the specials last.
List<int> seasonsOfSeries(Map<String, dynamic>? series) {
  final seasons = <int>{
    for (final season in jsonObjects(series?['seasons'], (each) => each))
      ?intOrNull(season['seasonNumber']),
  }.toList()..sort();
  if (seasons.remove(0)) seasons.add(0);
  return seasons;
}

/// A file's name without its extension, as J draws it:
/// `Kosmische.Wasserette.S01E01.1080p.WEB`. The extension is the same on
/// every row, and on a phone it is what pushes the episode code into the
/// ellipsis.
String fileStem(ManualImportItem item) {
  final name = item.fileName;
  final dot = name.lastIndexOf('.');
  return dot > 0 && name.length - dot <= 5 ? name.substring(0, dot) : name;
}

/// `S1`, or `Specials` for season 0.
String seasonChipLabel(int season) =>
    season == 0 ? 'Specials' : formatSeasonCode(season);

/// The resolution a quality name holds (`WEBDL-720p` is `720p`).
String? resolutionOf(String? qualityName) =>
    RegExp(r'\d{3,4}p').firstMatch(qualityName ?? '')?.group(0);

/// The quality of one group of clear files, in the page's words:
/// `1080p WEB · English · each replaces a 720p file`. A part the files do not
/// share is left out. [replacing] holds, by path, the quality of the library
/// file each one replaces.
String? clearQualityLine(
  List<ManualImportItem> files, {
  Map<String, String> replacing = const {},
}) {
  if (files.isEmpty) return null;
  String? shared(String? Function(ManualImportItem file) read) {
    final first = read(files.first);
    return files.every((file) => read(file) == first) ? first : null;
  }

  final quality = shared(
    (file) => file.qualityLabel == 'Unknown' ? null : file.qualityLabel,
  );
  final language = shared(
    (file) => file.languageLabel == 'Original' ? null : file.languageLabel,
  );
  final replaced = [
    for (final file in files)
      if (replacing[file.path] case final old?) resolutionOf(old) ?? old,
  ];
  String? replaces;
  if (replaced.isNotEmpty) {
    final same = replaced.every((old) => old == replaced.first);
    if (replaced.length == files.length && same) {
      replaces = files.length == 1
          ? 'replaces a ${replaced.first} file'
          : 'each replaces a ${replaced.first} file';
    } else {
      replaces = replaced.length == 1
          ? '1 replaces a file you have'
          : '${replaced.length} replace files you have';
    }
  }
  final parts = [
    if (quality != null) qualityWords(quality),
    ?language,
    ?replaces,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// What a clear row says first: `S1 E1`, `Track 3`, or for a movie its
/// quality and size.
String clearRowLabel(ServiceKey service, ManualImportItem item) {
  final identity = manualImportIdentityFor(service, item);
  if (service != ServiceKey.radarr && identity.code != null) {
    return identity.code!;
  }
  final quality = item.qualityLabel == 'Unknown'
      ? null
      : qualityWords(item.qualityLabel);
  return quality ?? item.fileName;
}

/// Season → episode numbers, for the episodes [files] carry.
Map<int, List<int>> episodesBySeason(Iterable<ManualImportItem> files) {
  final seasons = <int, Set<int>>{};
  for (final file in files) {
    for (final episode in file.episodes) {
      final season = intOrNull(episode['seasonNumber']);
      final number = intOrNull(episode['episodeNumber']);
      if (season == null || number == null) continue;
      seasons.putIfAbsent(season, () => {}).add(number);
    }
  }
  final ordered = seasons.keys.toList()..sort();
  return {
    for (final season in ordered) season: seasons[season]!.toList()..sort(),
  };
}

/// Each season's number of episodes, as a series' payload states it.
Map<int, int> seasonSizesOf(Map<String, dynamic>? series) {
  final sizes = <int, int>{};
  for (final season in jsonObjects(series?['seasons'], (each) => each)) {
    final number = intOrNull(season['seasonNumber']);
    final total =
        intOrNull(mapOrNull(season['statistics'])?['totalEpisodeCount']) ?? 0;
    if (number != null && total > 0) sizes[number] = total;
  }
  return sizes;
}

/// `S1 and S2 E1–E2`: each season's runs, a gap starting a new run, and a
/// season whole ([sizes] says how many episodes it has) by its code alone.
String? episodeRunsLine(
  Map<int, List<int>> bySeason, {
  Map<int, int> sizes = const {},
}) {
  final seasons = <String>[];
  for (final MapEntry(key: season, value: numbers) in bySeason.entries) {
    if (numbers.isEmpty) continue;
    final size = sizes[season];
    if (size != null &&
        numbers.length == size &&
        numbers.first == 1 &&
        numbers.last == size) {
      seasons.add(formatSeasonCode(season));
      continue;
    }
    final runs = <List<int>>[];
    for (final number in numbers) {
      if (runs.isNotEmpty && number == runs.last.last + 1) {
        runs.last.add(number);
      } else {
        runs.add([number]);
      }
    }
    final first = formatEpisodeRange(season, runs.first)!;
    seasons.add(
      [
        first,
        for (final run in runs.skip(1))
          run.length == 1
              ? formatEpisodeOrdinal(run.single)
              : '${formatEpisodeOrdinal(run.first)}'
                    '–${formatEpisodeOrdinal(run.last)}',
      ].join(', '),
    );
  }
  if (seasons.isEmpty) return null;
  if (seasons.length == 1) return seasons.single;
  return '${seasons.sublist(0, seasons.length - 1).join(', ')} and '
      '${seasons.last}';
}

/// `12 episodes imported`, `Big Buck Bunny imported`, `3 movies imported`;
/// while it runs, `Importing 12 episodes`.
String importHeadline(
  ServiceKey service,
  List<ManualImportItem> files, {
  bool done = true,
}) {
  final String what;
  switch (service) {
    case ServiceKey.sonarr:
      final count = files.fold<int>(
        0,
        (sum, file) => sum + (file.episodes.isEmpty ? 1 : file.episodes.length),
      );
      what = count == 1 ? '1 episode' : '$count episodes';
    case ServiceKey.radarr:
      what = files.length == 1
          ? manualImportGroupTitle(service, files.single)
          : '${files.length} movies';
    case _:
      final count = files.fold<int>(
        0,
        (sum, file) => sum + (file.tracks.isEmpty ? 1 : file.tracks.length),
      );
      what = count == 1 ? '1 track' : '$count tracks';
  }
  return done ? '$what imported' : 'Importing $what';
}

/// The step the import took, when every file replaced one at a single
/// resolution and arrived at a single quality: (`720p`, `1080p WEB`).
({String from, String to})? importedStep(
  List<ManualImportItem> files,
  Map<String, String> replacing,
) {
  if (files.isEmpty) return null;
  final old = {for (final file in files) resolutionOf(replacing[file.path])};
  final next = {
    for (final file in files)
      file.qualityLabel == 'Unknown' ? null : file.qualityLabel,
  };
  if (old.length != 1 || next.length != 1) return null;
  final from = old.single;
  final to = next.single;
  if (from == null || to == null) return null;
  return (from: from, to: qualityWords(to));
}

/// The sentence under the headline, for files of one title: `Cosmos
/// Laundromat S1 E1–E10 and S2 E1–E2 are now 1080p.`, or `… are in your
/// library.` when nothing was replaced. Null across several titles.
String? importedSentence(
  ServiceKey service,
  List<ManualImportItem> files,
  Map<String, String> replacing,
) {
  if (files.isEmpty) return null;
  final titles = {
    for (final file in files) manualImportGroupTitle(service, file),
  };
  if (titles.length != 1) return null;
  final title = titles.single;
  final step = importedStep(files, replacing);
  final now = step == null ? null : resolutionOf(step.to) ?? step.to;
  if (service == ServiceKey.sonarr) {
    final runs = episodeRunsLine(
      episodesBySeason(files),
      sizes: seasonSizesOf(files.first.series),
    );
    final subject = runs == null ? title : '$title $runs';
    final episodes = episodesBySeason(
      files,
    ).values.fold<int>(0, (sum, numbers) => sum + numbers.length);
    final verb = runs != null && episodes > 1 ? 'are' : 'is';
    return now == null
        ? '$subject $verb in your library.'
        : '$subject $verb now $now.';
  }
  if (service == ServiceKey.radarr && files.length == 1) {
    return now == null ? null : '$title is now $now.';
  }
  return now == null ? '$title is in your library.' : '$title is now $now.';
}

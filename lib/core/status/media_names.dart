/// The two names a copy of a title goes by: what it is, and which copy.
///
/// **The title says what; the machine name says which copy.** `Sprite Fright`
/// is a film, and `Sprite.Fright.2021.1080p.WEB` is one release of it a client
/// is moving. A row about a copy (a download, an acquisition, a blocked
/// release, the download clients' own lists) carries both; a row about a title
/// carries the title alone. This is the value those rows carry, built once
/// here from the services' own fields, so no surface invents its own clean-up
/// of a release name: a home-made one (dots to spaces, cut at the year) turns
/// out wrong titles stated with confidence.
library;

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// What a machine name names.
enum MachineNameKind {
  /// A release, as an indexer named it and a client moves it: a torrent's
  /// `name`, an NZB's, an arr queue record's `title`, a history or blocklist
  /// `sourceTitle`. Its copy action is "Copy release name".
  release,

  /// A file on disk: what an import became (`data.importedPath`, else
  /// `data.droppedPath`). Its copy action is "Copy file name".
  file,
}

/// Where a [MediaNames.title] came from.
enum MediaTitleSource {
  /// The arr's own item: the movie, the series and its episode, the album
  /// and its artist. On a client's row, through the arr record joined to it.
  library,

  /// The arr's parser (`/api/v3/parse`, `/api/v1/parse`), asked about a name
  /// no arr record claimed: the arr's own reading, never ours.
  parser,

  /// Nothing recognised the name: the title is the raw name, and there is no
  /// machine name beside it.
  raw,
}

/// A copy's title and machine name.
class MediaNames {
  const MediaNames({
    required this.title,
    required String this.machineName,
    required MachineNameKind this.machineKind,
    this.source = MediaTitleSource.library,
  });

  /// A name nothing recognised: it is the title, in its raw form, and there is
  /// no second name to set under it.
  const MediaNames.raw(String name)
    : title = name,
      machineName = null,
      machineKind = null,
      source = MediaTitleSource.raw;

  /// What the copy is: `Cosmos Laundromat · S2 E4`, `Album · Artist`.
  final String title;

  /// The exact string of the copy, as the service returned it, or null when
  /// the title already is that string.
  final String? machineName;

  /// What [machineName] names, null exactly when it is.
  final MachineNameKind? machineKind;

  final MediaTitleSource source;

  /// [title] is the copy's raw name: nothing recognised it.
  bool get isRaw => source == MediaTitleSource.raw;

  /// Names an arr record by its own item, with [machineName] beside it.
  ///
  /// Falls back to the raw name when the record names no item (an unknown
  /// grab), or when the item's name is the machine name itself; and to
  /// [fallback] when the record carries neither.
  factory MediaNames.ofRecord(
    Map<String, dynamic> record, {
    required String? machineName,
    MachineNameKind kind = MachineNameKind.release,
    String fallback = 'Unknown release',
  }) {
    final machine = machineName?.trim();
    final title = arrRecordTitle(record)?.trim();
    if (title == null || title.isEmpty) {
      return MediaNames.raw(
        machine == null || machine.isEmpty ? fallback : machine,
      );
    }
    if (machine == null || machine.isEmpty || machine == title) {
      return MediaNames.raw(title);
    }
    return MediaNames(title: title, machineName: machine, machineKind: kind);
  }

  /// This copy's title with [machineName] beside it when it has none of its
  /// own: a joined row whose arr record carried no release name keeps the
  /// client's.
  MediaNames withMachineName(String? machineName, MachineNameKind kind) {
    final machine = machineName?.trim();
    if (this.machineName != null || machine == null || machine.isEmpty) {
      return this;
    }
    if (isRaw) return this;
    return MediaNames(
      title: title,
      machineName: machine,
      machineKind: kind,
      source: source,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaNames &&
      other.title == title &&
      other.machineName == machineName &&
      other.machineKind == machineKind &&
      other.source == source;

  @override
  int get hashCode => Object.hash(title, machineName, machineKind, source);

  @override
  String toString() =>
      'MediaNames($title'
      '${machineName == null ? '' : ', ${machineKind?.name}: $machineName'}'
      ', ${source.name})';
}

/// What an arr queue, history or blocklist record is about, by the arr's own
/// item, or null when it names none.
///
/// `Sprite Fright`; `Cosmos Laundromat · S02E04`, the episode in the app's one
/// format ([formatArrEpisodeCode]); `Album · Artist`; `Book · Author`.
String? arrRecordTitle(Map<String, dynamic> record) {
  final album = arrAlbumTitle(record);
  if (album != null) return joinDisplayParts([album, arrArtistName(record)]);
  final book = arrBookTitle(record);
  if (book != null) return joinDisplayParts([book, arrAuthorName(record)]);
  final series = arrSeriesTitle(record);
  if (series != null) {
    return joinDisplayParts([series, arrEpisodeCode(record)]);
  }
  return arrPrimaryMediaTitle(record);
}

/// The names of an arr **history** record: for an import, the file it became
/// (`data.importedPath`, else `data.droppedPath`); for anything else the
/// release it was grabbed as (`sourceTitle`).
MediaNames arrHistoryNames(Map<String, dynamic> record) {
  final data = mapOrNull(record['data']);
  final file =
      stringOrNull(data?['importedPath']) ?? stringOrNull(data?['droppedPath']);
  return file != null
      ? MediaNames.ofRecord(
          record,
          machineName: file,
          kind: MachineNameKind.file,
          fallback: 'History item',
        )
      : MediaNames.ofRecord(
          record,
          machineName: stringOrNull(record['sourceTitle']),
          fallback: 'History item',
        );
}

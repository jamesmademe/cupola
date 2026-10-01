import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A file an arr keeps in its library: Radarr's `movieFile`, Sonarr's
/// `episodeFile`.
///
/// The two resources share these fields in the v3 API (`MovieFileResource`,
/// `EpisodeFileResource`), so one model reads both. Radarr embeds it in the
/// movie resource whenever the movie has a file.
///
/// The names are machine strings and are kept exactly as they arrived: a
/// blank one is absent, anything else is not trimmed or tidied.
class ArrMediaFile {
  const ArrMediaFile({
    this.relativePath,
    this.path,
    this.size,
    this.sceneName,
    this.originalFilePath,
    this.qualityName,
    this.dateAdded,
  });

  /// The file, relative to the item's own folder:
  /// `Coffee Run (2020) WEBDL-1080p.mkv`, as the arr named it on import.
  final String? relativePath;

  /// The file's absolute path on the server.
  final String? path;

  /// Bytes on disk, when the arr reported them.
  final int? size;

  /// The release the file was imported from, without an extension
  /// (`Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD`), when the arr knew
  /// it. A manual import usually has none.
  final String? sceneName;

  /// Where the file sat in the download, relative to the download's folder.
  /// The arr's fallback record of the original name.
  final String? originalFilePath;

  /// `Bluray-1080p`.
  final String? qualityName;

  final DateTime? dateAdded;

  factory ArrMediaFile.fromJson(Map<String, dynamic> json) {
    final quality = mapOrNull(json['quality']);
    return ArrMediaFile(
      relativePath: _name(json['relativePath']),
      path: _name(json['path']),
      size: intOrNull(json['size']),
      sceneName: _name(json['sceneName']),
      originalFilePath: _name(json['originalFilePath']),
      qualityName: stringOrNull(
        mapOrNull(quality?['quality'])?['name'] ?? quality?['name'],
      ),
      dateAdded: DateTime.tryParse('${json['dateAdded'] ?? ''}'),
    );
  }

  /// The file's name in full, the way the library holds it: the relative path,
  /// or the last part of the absolute one. Null when the arr sent neither.
  String? get fileName => relativePath ?? _lastSegment(path);

  /// The name the file was released under, when the arr renamed it on import.
  ///
  /// The scene name first, then the original file path. Null when the file
  /// still carries that name (an arr keeps the release name when renaming is
  /// off, and a scene name has no extension, so the comparison drops it), or
  /// when the arr recorded no original at all.
  String? get releasedAs {
    final current = _lastSegment(fileName);
    if (current == null) return null;

    final scene = sceneName;
    if (scene != null) {
      if (scene == current || scene == _withoutExtension(current)) return null;
      return scene;
    }

    final original = originalFilePath;
    if (original == null ||
        original == fileName ||
        _lastSegment(original) == current) {
      return null;
    }
    return original;
  }
}

/// A name exactly as sent, or null when there is nothing in it.
String? _name(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String? _lastSegment(String? value) {
  if (value == null) return null;
  final last = value.split(RegExp(r'[\\/]')).last;
  return last.isEmpty ? null : last;
}

final _extension = RegExp(r'\.[A-Za-z0-9]{1,8}$');

String _withoutExtension(String name) => name.replaceFirst(_extension, '');

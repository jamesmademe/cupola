import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// The file Sonarr holds for an episode (`/api/v3/episodefile`): what an
/// episode's sheet says it has on disk.
class SonarrEpisodeFile {
  const SonarrEpisodeFile({
    required this.id,
    required this.relativePath,
    this.qualityName,
    this.size,
    this.dateAdded,
    this.cutoffNotMet = false,
  });

  final int id;

  /// The file's name under the series folder, as Sonarr wrote it: a machine
  /// string, drawn as it came.
  final String relativePath;

  /// Sonarr's name for the quality, `WEBDL-720p`.
  final String? qualityName;

  final int? size;
  final DateTime? dateAdded;

  /// The file is below the quality its profile asks for: Sonarr keeps
  /// looking.
  final bool cutoffNotMet;

  factory SonarrEpisodeFile.fromJson(Map<String, dynamic> json) {
    final quality = mapOrNull(mapOrNull(json['quality'])?['quality']);
    final relative = stringOrNull(json['relativePath']) ?? '';
    final path = stringOrNull(json['path']) ?? '';
    return SonarrEpisodeFile(
      id: intOrNull(json['id']) ?? 0,
      // The name alone, without the season folder in front of it.
      relativePath: (relative.isNotEmpty ? relative : path).split('/').last,
      qualityName: stringOrNull(quality?['name']),
      size: intOrNull(json['size']),
      dateAdded: DateTime.tryParse(stringOrNull(json['dateAdded']) ?? ''),
      cutoffNotMet: json['qualityCutoffNotMet'] == true,
    );
  }
}

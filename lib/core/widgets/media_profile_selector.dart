import 'package:cupola/core/widgets/media_detail_value_row.dart';

/// Radarr/Sonarr/Lidarr quality profiles as picker options.
///
/// The arr clients all hand these back as untyped `{'id': int, 'name': String}`
/// maps, so the cast lives in exactly one place instead of at every call site.
/// Entries missing either key are dropped rather than rendered as a blank row
/// with an id behind it.
List<MediaDetailValueOption<int>> qualityProfileOptions(
  List<Map<String, dynamic>> qualityProfiles,
) {
  return [
    for (final profile in qualityProfiles)
      if (profile['id'] is int && profile['name'] is String)
        MediaDetailValueOption<int>(
          value: profile['id'] as int,
          label: profile['name'] as String,
        ),
  ];
}

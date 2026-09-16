import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/widgets/media_detail_value_row.dart';

/// Opens the quality profile picker as a sheet.
///
/// A top-level function rather than a static, per the house convention for sheet
/// helpers.
///
/// It is now a thin wrapper over [showMediaValueSheet], which is the one
/// one-field sheet decision 25 puts behind every in-place edit. It kept its own
/// copy of the sheet and the option row until the generic row existed; two
/// implementations of "pick one of these and write it" is exactly the kind of
/// drift that ends with two different selected-row treatments.
///
/// Returns after [onProfileSelected] has been awaited, and only calls it when
/// the chosen profile actually differs from [currentProfileId] — a no-op write
/// to a quality profile can queue a library-wide upgrade sweep.
///
/// [accent] lights the sheet and the selected row. Pass the page's service
/// accent; without it the picker would put `colorScheme.primary` indigo on a
/// Sonarr violet page, which is a second accent on one screen.
Future<void> showMediaProfileSelector(
  BuildContext context, {
  required String currentProfileName,
  required int? currentProfileId,
  required List<Map<String, dynamic>> qualityProfiles,
  required Future<void> Function(int profileId) onProfileSelected,
  Color? accent,
  bool enableHaptics = true,
}) async {
  if (qualityProfiles.isEmpty) return;

  if (enableHaptics) {
    HapticFeedback.selectionClick();
  }

  final picked = await showMediaValueSheet<int>(
    context,
    title: 'Quality profile',
    value: currentProfileId,
    currentLabel: currentProfileName,
    options: qualityProfileOptions(qualityProfiles),
    accent: accent,
  );

  if (picked != null && picked.value != currentProfileId) {
    await onProfileSelected(picked.value);
  }
}

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

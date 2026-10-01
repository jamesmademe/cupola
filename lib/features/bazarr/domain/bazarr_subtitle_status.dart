import 'package:cupola/core/status/media_status.dart';

/// Resolves a Bazarr movie/series monitoring state into the shared status
/// vocabulary, per the rule that statuses are built in a feature's `domain/`
/// layer and never assembled inside a widget.
///
/// The badge deliberately reports *monitoring*, preserving the copy the old
/// header pill used ("Monitored" / "Unmonitored"); subtitle coverage is
/// carried separately by the "N missing" metadata item and the Missing
/// Subtitles section, so a green badge never sits above a list of gaps
/// claiming completeness it doesn't have.
///
/// [monitored] is null when the record never arrived — a lookup that failed or
/// is still running behind a wanted item — and that is "Unknown", never the
/// "Unmonitored" a `?? false` used to put on a title Bazarr may well watch.
MediaStatusInfo bazarrSubtitleStatus({required bool? monitored}) {
  if (monitored == null) return const MediaStatusInfo.unknown();
  if (!monitored) {
    return const MediaStatusInfo(
      unmonitored: true,
      labelOverride: 'Unmonitored',
      toneOverride: StatusTone.neutral,
    );
  }
  return const MediaStatusInfo(
    labelOverride: 'Monitored',
    toneOverride: StatusTone.success,
  );
}

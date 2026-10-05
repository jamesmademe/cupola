/// Which of a series' episodes Sonarr looks for once it is added: Sonarr's
/// `addOptions.monitor`.
///
/// The values both Sonarr 3 and Sonarr 4 accept: Sonarr 4 renamed
/// `latestSeason` to `lastSeason` and still takes the old word, so the old
/// word is the one sent.
enum SonarrMonitor {
  all,
  future,
  missing,
  existing,
  firstSeason,
  latestSeason,
  none;

  /// The string Sonarr expects.
  String get wireValue => name;

  /// Sonarr's own name for it, in the app's case.
  String get label => switch (this) {
    SonarrMonitor.all => 'All episodes',
    SonarrMonitor.future => 'Future episodes',
    SonarrMonitor.missing => 'Missing episodes',
    SonarrMonitor.existing => 'Existing episodes',
    SonarrMonitor.firstSeason => 'First season',
    SonarrMonitor.latestSeason => 'Latest season',
    SonarrMonitor.none => 'None',
  };

  /// What choosing it means, under the label.
  String get meaning => switch (this) {
    SonarrMonitor.all => 'Every episode, aired and to come',
    SonarrMonitor.future => 'Only the ones that air from now',
    SonarrMonitor.missing => 'The aired ones without a file, and the new ones',
    SonarrMonitor.existing => 'The ones on disk, and the new ones',
    SonarrMonitor.firstSeason => 'Season 1 alone',
    SonarrMonitor.latestSeason => 'The latest season alone',
    SonarrMonitor.none => 'Lists it and looks for nothing',
  };
}

/// The three values Sonarr accepts for a series's `seriesType`.
///
/// Not a free-text field and not a label: it decides how Sonarr reads episode
/// numbers out of a release name, which is why getting it wrong on an anime is
/// the classic reason nothing ever imports. `standard` expects `S01E02`,
/// `daily` expects a date, `anime` expects an absolute episode number.
///
/// Pure Dart, in `domain/`, because both the picker and the write need the same
/// three values and the wire strings are Sonarr's, not ours: a fourth value
/// arriving from a server we have not seen must not crash the detail page, so
/// [fromWire] answers null rather than throwing and the row falls back to
/// printing whatever Sonarr said.
enum SonarrSeriesType {
  standard,
  daily,
  anime;

  /// The string Sonarr stores and expects back. Identical to [name] today; it
  /// exists so a caller never has to know that, and so a future value whose
  /// Dart name cannot match the wire string has somewhere to diverge.
  String get wireValue => name;

  /// Title case, the way Sonarr's own UI writes it.
  String get label => switch (this) {
    SonarrSeriesType.standard => 'Standard',
    SonarrSeriesType.daily => 'Daily',
    SonarrSeriesType.anime => 'Anime',
  };

  /// What choosing this actually changes: the picker prints it under the
  /// label, because "Anime" on its own tells a first-time user nothing about
  /// why their episodes are not importing.
  String get description => switch (this) {
    SonarrSeriesType.standard => 'Episodes numbered by season, S01E02',
    SonarrSeriesType.daily => 'Episodes identified by air date',
    SonarrSeriesType.anime => 'Episodes numbered absolutely, from one',
  };

  /// The matching type for a raw Sonarr value, or null when it names something
  /// this app does not know.
  static SonarrSeriesType? fromWire(String? raw) {
    if (raw == null) return null;
    final needle = raw.trim().toLowerCase();
    for (final type in SonarrSeriesType.values) {
      if (type.wireValue == needle) return type;
    }
    return null;
  }
}

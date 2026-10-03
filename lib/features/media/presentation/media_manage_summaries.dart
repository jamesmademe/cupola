import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// The one line each closed operator section says (*Manage*), or
/// null when no arr copy has answered: there is nothing to manage yet.
///
/// - Files & quality: `2 files · 1080p Bluray, 2160p Remux`.
/// - History: when each copy was imported, `Imported Sat 12 Sep · Radarr · 4K
///   Fri 2 Oct`.
/// - Subtitles: Bazarr's languages, `EN · IT · DE wanted`; null without a
///   Bazarr that follows a copy, and the section is left out.
/// - Search releases: the connections a search can go to.
({String files, String history, String? subtitles, String search})?
mediaManageSummaries(
  List<MediaRow> rows, {
  required String Function(ServiceInstance connection) title,
}) {
  final copies =
      <({ServiceInstance connection, String? quality, DateTime? added})>[];
  String? subtitles;
  for (final row in rows) {
    if (row case MediaConnectionRow(
      :final connection,
      reading: MediaReadingAnswered(:final answer),
    )) {
      switch (answer.value) {
        case MediaRadarrCopy(:final movie?):
          final file = movie.movieFile;
          copies.add((
            connection: connection,
            quality: file?.qualityName,
            added: file?.dateAdded,
          ));
        case MediaSonarrCopy(series: _?):
          // A series' files are per episode: the section reads them on
          // opening.
          copies.add((connection: connection, quality: null, added: null));
        case MediaBazarrCopy(:final movie?):
          final present = movie.presentLanguages
              .map((language) => (language.code2 ?? '').toUpperCase())
              .where((code) => code.isNotEmpty);
          final missing = movie.missingLanguages
              .map((language) => (language.code2 ?? '').toUpperCase())
              .where((code) => code.isNotEmpty);
          subtitles = [
            ...present,
            if (missing.isNotEmpty) '${missing.join(' · ')} wanted',
          ].join(' · ');
      }
    }
  }
  if (copies.isEmpty) return null;

  final files = copies.where((copy) => (copy.quality ?? '').isNotEmpty);
  final names = copies.map((copy) => title(copy.connection)).toList();
  final imported = [
    for (final copy in copies)
      if (copy.added case final added?)
        copies.length == 1
            ? 'Imported ${formatShortDate(added.toIso8601String())}'
            : '${title(copy.connection)} ${formatShortDate(added.toIso8601String())}',
  ];
  return (
    files: files.isEmpty
        ? 'No file yet'
        : '${countLabel(files.length, 'file')} · '
              '${files.map((copy) => qualityWords(copy.quality!)).join(', ')}',
    history: imported.isEmpty
        ? ''
        : copies.length == 1
        ? imported.single
        : 'Imported ${imported.join(' · ')}',
    subtitles: subtitles,
    search: names.length <= 1
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  );
}

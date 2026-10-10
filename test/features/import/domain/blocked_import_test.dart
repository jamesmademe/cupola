import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/blocked_import_world.dart';

ManualImportItem _clear(int season, int episode) =>
    ManualImportItem.fromJson(cosmosClearFile(season, episode));

ManualImportItem _tape(int n) => ManualImportItem.fromJson(cosmosTapeFile(n));

void main() {
  group('blockedImportCauseOf', () {
    test("reads the arr's own messages", () {
      expect(
        blockedImportCauseOf([cosmosMessage]),
        BlockedImportCause.namesDontMatch,
      );
      expect(
        blockedImportCauseOf([
          'Found matching movie via grab history, but release was matched to '
              'movie by ID. Manual Import required.',
        ]),
        BlockedImportCause.namesDontMatch,
      );
      expect(
        blockedImportCauseOf(['Not an upgrade for existing episode file(s)']),
        BlockedImportCause.notAnUpgrade,
      );
      expect(
        blockedImportCauseOf(['Unable to parse file']),
        BlockedImportCause.unrecognised,
      );
      expect(
        blockedImportCauseOf([
          'One or more episodes expected in this release were not imported '
              'or missing',
        ]),
        BlockedImportCause.incomplete,
      );
      expect(
        blockedImportCauseOf(['Something new', null]),
        BlockedImportCause.unknown,
      );
      expect(blockedImportCauseOf(const []), BlockedImportCause.unknown);
    });

    test('the first message it knows decides', () {
      expect(
        blockedImportCauseOf(['Something new', 'Unable to parse file']),
        BlockedImportCause.unrecognised,
      );
    });
  });

  test('eighteen downloads stopped for one reason say it once', () {
    expect(
      distinctMessages([cosmosMessage, ' $cosmosMessage', null, '', 'Other']),
      [cosmosMessage, 'Other'],
    );
  });

  group('the words of the eighteen Cosmos downloads', () {
    test('the title counts files', () {
      expect(blockedImportTitle(18), 'Review 18 imports');
      expect(blockedImportTitle(1), 'Review the import');
    });

    test('the sentence under it', () {
      expect(
        blockedImportExplanation(
          ServiceKey.sonarr,
          BlockedImportCause.namesDontMatch,
          one: false,
        ),
        "The file names don't match the series name, so Sonarr won't guess.",
      );
      expect(
        blockedImportExplanation(
          ServiceKey.radarr,
          BlockedImportCause.namesDontMatch,
          one: true,
        ),
        "The file name doesn't match the movie's name, so Radarr won't guess.",
      );
      expect(
        blockedImportExplanation(
          ServiceKey.sonarr,
          BlockedImportCause.unknown,
          one: false,
        ),
        "Sonarr finished them and won't import them on its own.",
      );
    });

    test('in plain words', () {
      expect(
        blockedImportPlainWords(
          ServiceKey.sonarr,
          BlockedImportCause.namesDontMatch,
          title: 'Cosmos Laundromat',
          total: 18,
          unnamed: 6,
        ),
        'Sonarr grabbed these for Cosmos Laundromat, but their names '
        "don't say so. 12 name their episode clearly; 6 don't.",
      );
      expect(
        blockedImportPlainWords(
          ServiceKey.sonarr,
          BlockedImportCause.namesDontMatch,
          total: 3,
          unnamed: 0,
        ),
        'All 3 name their episode clearly.',
      );
      expect(
        blockedImportPlainWords(
          ServiceKey.sonarr,
          BlockedImportCause.unrecognised,
          total: 2,
          unnamed: 2,
        ),
        "Sonarr reads a file's name to know what it is. None of the 2 names "
        'its episode.',
      );
      // No words for a message the app does not know: the arr's own stand.
      expect(
        blockedImportPlainWords(
          ServiceKey.sonarr,
          BlockedImportCause.unknown,
          total: 2,
          unnamed: 0,
        ),
        isNull,
      );
    });
  });

  group('splitBlockedImport', () {
    test('a file is clear only when the arr would take it as it is', () {
      final refused = ManualImportItem.fromJson({
        ...cosmosClearFile(1, 3),
        'path': '/downloads/refused.mkv',
        'rejections': [
          {
            'reason': 'Not an upgrade for existing episode file(s)',
            'type': 'permanent',
          },
        ],
      });
      final sample = ManualImportItem.fromJson({
        ...cosmosClearFile(1, 4),
        'path': '/downloads/sample.mkv',
        'rejections': [
          {'reason': 'Sample', 'type': 'permanent'},
        ],
      });
      final nfo = ManualImportItem.fromJson({
        ...cosmosClearFile(1, 5),
        'path': '/downloads/info.nfo',
      });
      final split = splitBlockedImport(ServiceKey.sonarr, [
        _clear(1, 1),
        _tape(1),
        refused,
        sample,
        nfo,
      ]);
      expect([for (final file in split.clear) file.path], [_clear(1, 1).path]);
      // Matched whole and refused anyway: importing it replaces a file in
      // the library, so it is the user's to decide.
      expect(
        [for (final file in split.needYou) file.path],
        [_tape(1).path, '/downloads/refused.mkv'],
      );
      expect(split.leftOut, 2);
    });

    test('what each file that needs the user asks for', () {
      expect(needYouKindOf(ServiceKey.sonarr, _tape(1)), NeedYouKind.episode);
      final unknown = ManualImportItem.fromJson({
        ...cosmosTapeFile(2),
        'series': null,
      });
      expect(needYouKindOf(ServiceKey.sonarr, unknown), NeedYouKind.identity);
      expect(
        needYouKindOf(ServiceKey.sonarr, _clear(1, 1)),
        NeedYouKind.refused,
      );
    });

    test('the sentence under `6 need you`', () {
      expect(
        needYouExplanation(ServiceKey.sonarr, [
          NeedYouKind.episode,
          NeedYouKind.episode,
        ], one: false),
        "Sonarr can't tell which episode these are. Pick the season and "
        'episode for each.',
      );
      expect(
        needYouExplanation(ServiceKey.sonarr, [
          NeedYouKind.episode,
          NeedYouKind.refused,
        ], one: false),
        'Each needs a choice before it can go in.',
      );
    });
  });

  group('the picker', () {
    test('starts on the episode the name carries', () {
      expect(episodeNumberInName('Laundromat.Tapes.E03.720p.WEB.mkv'), 3);
      expect(episodeNumberInName('Show - Ep12 - Title.mkv'), 12);
      expect(episodeNumberInName('Show.Episode.7.mkv'), 7);
      expect(episodeNumberInName('Show.S01E04.mkv'), isNull);
      expect(episodeNumberInName('Something.WEB.mkv'), isNull);
    });

    test('offers the seasons the series has, the specials last', () {
      expect(seasonsOfSeries(cosmosSeries), [1, 2, 3, 0]);
      expect(seasonChipLabel(0), 'Specials');
      expect(seasonChipLabel(2), 'S2');
      expect(seasonsOfSeries(null), isEmpty);
    });
  });

  group('clearQualityLine', () {
    final files = [for (final (s, e) in cosmosClearEpisodes) _clear(s, e)];

    test("J's line: the quality, the language, what each replaces", () {
      expect(
        clearQualityLine(
          files,
          replacing: {for (final file in files) file.path: 'HDTV-720p'},
        ),
        '1080p WEB · English · each replaces a 720p file',
      );
    });

    test('says only what the files share', () {
      expect(clearQualityLine([files.first, _tape(1)]), 'English');
      expect(
        clearQualityLine(
          files.take(3).toList(),
          replacing: {files.first.path: 'HDTV-720p'},
        ),
        '1080p WEB · English · 1 replaces a file you have',
      );
    });
  });

  group('after the import', () {
    final files = [for (final (s, e) in cosmosClearEpisodes) _clear(s, e)];
    final replacing = {for (final file in files) file.path: 'HDTV-720p'};

    test('the headline counts what went in', () {
      expect(importHeadline(ServiceKey.sonarr, files), '12 episodes imported');
      expect(
        importHeadline(ServiceKey.sonarr, files, done: false),
        'Importing 12 episodes',
      );
      final movie = ManualImportItem.fromJson({
        'path': '/downloads/bbb.mkv',
        'movie': {'id': 3, 'title': 'Big Buck Bunny'},
      });
      expect(
        importHeadline(ServiceKey.radarr, [movie]),
        'Big Buck Bunny imported',
      );
    });

    test('the sentence names the runs and the step', () {
      expect(
        importedSentence(ServiceKey.sonarr, files, replacing),
        'Cosmos Laundromat S1 E1–E10 and S2 E1–E2 are now 1080p.',
      );
      expect(
        importedSentence(ServiceKey.sonarr, [files.first], const {}),
        'Cosmos Laundromat S1 E1 is in your library.',
      );
      expect(importedStep(files, replacing), (from: '720p', to: '1080p WEB'));
      expect(importedStep(files, const {}), isNull);
    });

    test('a whole season is named by its code', () {
      final whole = [
        for (final (s, e) in cosmosClearEpisodes)
          ManualImportItem.fromJson({
            ...cosmosClearFile(s, e),
            'series': {
              ...cosmosSeries,
              'seasons': [
                {
                  'seasonNumber': 1,
                  'statistics': {'totalEpisodeCount': 10},
                },
                {
                  'seasonNumber': 2,
                  'statistics': {'totalEpisodeCount': 10},
                },
              ],
            },
          }),
      ];
      expect(
        importedSentence(ServiceKey.sonarr, whole, {
          for (final file in whole) file.path: 'HDTV-720p',
        }),
        'Cosmos Laundromat S1 and S2 E1–E2 are now 1080p.',
      );
    });

    test('a gap starts a new run', () {
      expect(
        episodeRunsLine({
          1: [1, 2, 3, 5],
          3: [7],
        }),
        'S1 E1–E3, E5 and S3 E7',
      );
    });
  });
}

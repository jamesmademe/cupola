import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';

void main() {
  group('MediaNames.ofRecord', () {
    test('a movie record: the arr\'s title, the release beside it', () {
      final names = MediaNames.ofRecord({
        'movie': {'title': 'Sprite Fright', 'year': 2021},
        'title': 'Sprite.Fright.2021.1080p.WEB',
      }, machineName: 'Sprite.Fright.2021.1080p.WEB');
      expect(names.title, 'Sprite Fright');
      expect(names.machineName, 'Sprite.Fright.2021.1080p.WEB');
      expect(names.machineKind, MachineNameKind.release);
      expect(names.source, MediaTitleSource.library);
    });

    test('an episode record carries its episode, an album its artist', () {
      expect(
        MediaNames.ofRecord({
          'series': {'title': 'Cosmos Laundromat'},
          'episode': {'seasonNumber': 2, 'episodeNumber': 4},
        }, machineName: 'Cosmos.Laundromat.S02E04.1080p.WEB').title,
        startsWith('Cosmos Laundromat\u00A0· S'),
      );
      expect(
        MediaNames.ofRecord({
          'album': {'title': 'Nosferatu'},
          'artist': {'artistName': 'Hans Erdmann'},
        }, machineName: 'Hans.Erdmann-Nosferatu-FLAC').title,
        'Nosferatu\u00A0· Hans Erdmann',
      );
    });

    test('a record naming no item is its raw name, with no second name; '
        'nothing at all is the fallback', () {
      final raw = MediaNames.ofRecord(const {
        'title': 'Some.Release.2020',
      }, machineName: 'Some.Release.2020');
      expect(raw.title, 'Some.Release.2020');
      expect(raw.machineName, isNull);
      expect(raw.machineKind, isNull);
      expect(raw.isRaw, isTrue);

      expect(
        MediaNames.ofRecord(const {}, machineName: null).title,
        'Unknown release',
      );
      expect(
        MediaNames.ofRecord(
          const {},
          machineName: ' ',
          fallback: 'Blocked release',
        ).title,
        'Blocked release',
      );
    });

    test('a release named exactly like its title has no second name', () {
      final names = MediaNames.ofRecord(const {
        'movie': {'title': 'Sintel'},
      }, machineName: 'Sintel');
      expect(names.machineName, isNull);
    });
  });

  group('arrHistoryNames', () {
    test('an import names the file it became', () {
      final names = arrHistoryNames(const {
        'movie': {'title': 'Coffee Run'},
        'eventType': 'downloadFolderImported',
        'sourceTitle': 'Coffee.Run.2020.1080p',
        'data': {
          'droppedPath': '/downloads/Coffee.Run.2020.mkv',
          'importedPath': '/films/Coffee Run (2020)/Coffee Run (2020).mkv',
        },
      });
      expect(names.title, 'Coffee Run');
      expect(
        names.machineName,
        '/films/Coffee Run (2020)/Coffee Run (2020).mkv',
      );
      expect(names.machineKind, MachineNameKind.file);
    });

    test('a dropped path stands in when there is no imported one; a grab '
        'names its release', () {
      expect(
        arrHistoryNames(const {
          'movie': {'title': 'Coffee Run'},
          'data': {'droppedPath': '/downloads/Coffee.Run.2020.mkv'},
        }).machineName,
        '/downloads/Coffee.Run.2020.mkv',
      );
      final grab = arrHistoryNames(const {
        'movie': {'title': 'Coffee Run'},
        'eventType': 'grabbed',
        'sourceTitle': 'Coffee.Run.2020.1080p',
        'data': {'indexer': 'Fjord Tracker'},
      });
      expect(grab.machineName, 'Coffee.Run.2020.1080p');
      expect(grab.machineKind, MachineNameKind.release);
    });
  });

  test('withMachineName fills a missing release, never replaces one, and '
      'leaves a raw name alone', () {
    const named = MediaNames(
      title: 'Sprite Fright',
      machineName: 'Sprite.Fright.2021.1080p.WEB',
      machineKind: MachineNameKind.release,
    );
    expect(
      named.withMachineName('other', MachineNameKind.release),
      same(named),
    );
    expect(
      const MediaNames.raw(
        'ubuntu.iso',
      ).withMachineName('ubuntu.iso', MachineNameKind.release).machineName,
      isNull,
    );
  });
}

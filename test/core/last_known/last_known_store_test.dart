import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';

void main() {
  final at = DateTime(2026, 10, 12, 20, 53);

  group('an entry', () {
    test(
      'is read back for the connections and the shape it was written for',
      () {
        final store = LastKnownStore.memory()
          ..write(
            'home.featured',
            validity: 'radarr:radarr:http://nas:7878',
            schema: 1,
            data: {'title': 'Dune'},
            takenAt: at,
          );

        final entry = store.read(
          'home.featured',
          validity: 'radarr:radarr:http://nas:7878',
          schema: 1,
        );
        expect(entry?.data, {'title': 'Dune'});
        expect(entry?.takenAt, at);
      },
    );

    test('read for other connections is dropped, and stays dropped', () {
      // The id survives a change of address and a sign-in as somebody else:
      // what was read for one account is never drawn for another.
      final store = LastKnownStore.memory()
        ..write(
          'home.requests',
          validity: 'seerr:seerr:http://nas:5055:user 1',
          schema: 1,
          data: const ['a'],
          takenAt: at,
        );

      expect(
        store.read(
          'home.requests',
          validity: 'seerr:seerr:http://nas:5055:user 2',
          schema: 1,
        ),
        isNull,
      );
      expect(
        store.read(
          'home.requests',
          validity: 'seerr:seerr:http://nas:5055:user 1',
          schema: 1,
        ),
        isNull,
      );
    });

    test('of another shape is dropped', () {
      final store = LastKnownStore.memory()
        ..write('s', validity: 'v', schema: 1, data: 1, takenAt: at);
      expect(store.read('s', validity: 'v', schema: 2), isNull);
    });

    test('too large is not kept, and takes the old one with it', () {
      final store = LastKnownStore.memory()
        ..write('s', validity: 'v', schema: 1, data: 'old', takenAt: at)
        ..write(
          's',
          validity: 'v',
          schema: 1,
          data: 'x' * (LastKnownStore.maxEntryBytes + 1),
          takenAt: at,
        );
      expect(store.read('s', validity: 'v', schema: 1), isNull);
    });

    test('that is not JSON is not kept', () {
      final store = LastKnownStore.memory()
        ..write('s', validity: 'v', schema: 1, data: 'old', takenAt: at)
        ..write('s', validity: 'v', schema: 1, data: Object(), takenAt: at);
      expect(store.read('s', validity: 'v', schema: 1), isNull);
    });
  });

  group('what an entry was written from', () {
    test('is held until another write, a mismatch or a clear', () async {
      final source = Object();
      final store = LastKnownStore.memory()
        ..write(
          's',
          validity: 'v',
          schema: 1,
          data: 1,
          takenAt: at,
          source: source,
        );
      expect(store.holds('s', validity: 'v', source: source), isTrue);
      // The same answer for other connections is not held: it was not
      // written for them.
      expect(store.holds('s', validity: 'w', source: source), isFalse);
      expect(store.holds('s', validity: 'v', source: Object()), isFalse);

      await store.clear();
      // A reset forgets it too, so the same answer is written again.
      expect(store.holds('s', validity: 'v', source: source), isFalse);
    });
  });

  group('the file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('last_known'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps the entries across a start', () async {
      final file = File('${dir.path}/last_known.json');
      final first = await LastKnownStore.open(file);
      first.write(
        'home.featured',
        validity: 'v',
        schema: 3,
        data: {
          'slides': [1, 2],
        },
        takenAt: at,
      );
      await first.flush();

      final second = await LastKnownStore.open(file);
      final entry = second.read('home.featured', validity: 'v', schema: 3);
      expect(entry?.data, {
        'slides': [1, 2],
      });
      expect(entry?.takenAt, at);
    });

    test('missing, broken or of another version is an empty store', () async {
      final missing = await LastKnownStore.open(File('${dir.path}/none.json'));
      expect(missing.read('s', validity: 'v', schema: 1), isNull);

      final broken = File('${dir.path}/broken.json')..writeAsStringSync('{');
      expect(
        (await LastKnownStore.open(broken)).read('s', validity: 'v', schema: 1),
        isNull,
      );

      final foreign = File('${dir.path}/foreign.json')
        ..writeAsStringSync(
          jsonEncode({
            'version': LastKnownStore.version + 1,
            'entries': {
              's': {
                'takenAt': at.toUtc().toIso8601String(),
                'validity': 'v',
                'schema': 1,
                'data': 1,
              },
            },
          }),
        );
      expect(
        (await LastKnownStore.open(
          foreign,
        )).read('s', validity: 'v', schema: 1),
        isNull,
      );
    });

    test('cleared is empty on the next start too', () async {
      final file = File('${dir.path}/last_known.json');
      final store = await LastKnownStore.open(file);
      store.write('s', validity: 'v', schema: 1, data: 1, takenAt: at);
      await store.flush();
      await store.clear();

      final next = await LastKnownStore.open(file);
      expect(next.read('s', validity: 'v', schema: 1), isNull);
    });
  });
}

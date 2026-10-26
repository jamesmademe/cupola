import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/artwork_cache_migration.dart';

void main() {
  late Directory temp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('artwork_migration_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  Future<Directory> dir() async => temp;

  test(
    'removes the legacy poster directory once and leaves others alone',
    () async {
      final legacy = Directory('${temp.path}/$legacyArtworkCacheDirectory')
        ..createSync();
      File('${legacy.path}/poster.jpg').writeAsBytesSync([1, 2, 3]);
      final current = Directory('${temp.path}/cupola_artwork')..createSync();

      final removed = await removeLegacyArtworkCache(
        prefs: await prefs(),
        temporaryDirectory: dir,
      );

      expect(removed, isTrue);
      expect(legacy.existsSync(), isFalse);
      expect(current.existsSync(), isTrue);
    },
  );

  test(
    'does nothing on later launches, even if the directory returns',
    () async {
      final store = await prefs();
      await removeLegacyArtworkCache(prefs: store, temporaryDirectory: dir);
      final legacy = Directory('${temp.path}/$legacyArtworkCacheDirectory')
        ..createSync();

      final again = await removeLegacyArtworkCache(
        prefs: store,
        temporaryDirectory: dir,
      );

      expect(again, isFalse);
      expect(legacy.existsSync(), isTrue);
    },
  );

  test('a fresh install with no legacy directory is marked done', () async {
    final store = await prefs();

    final removed = await removeLegacyArtworkCache(
      prefs: store,
      temporaryDirectory: dir,
    );

    expect(removed, isTrue);
    expect(store.getBool('artwork_cache_legacy_removed'), isTrue);
  });

  test('a failure is swallowed and retried on the next launch', () async {
    final store = await prefs();

    final removed = await removeLegacyArtworkCache(
      prefs: store,
      temporaryDirectory: () async => throw const FileSystemException('gone'),
    );

    expect(removed, isFalse);
    expect(store.getBool('artwork_cache_legacy_removed'), isNull);
  });
}

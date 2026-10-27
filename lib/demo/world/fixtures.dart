import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, AssetManifest;

/// The recorded service answers the world serves as they are (`plex/identity.json`
/// and the like), kept once in `test/fixtures/` for the model tests and the
/// world alike.
///
/// The app has no `test/` folder to read: the files the world names are
/// declared as assets in `pubspec.yaml` (held by
/// `test/demo/world_fixtures_guard_test.dart`) and the demo reads them into
/// memory with [preload] before the world answers its first request. A test
/// never preloads and reads the file from the package root.
abstract final class WorldFixtures {
  /// Where the fixtures live, as a path from the package root and as the
  /// asset key prefix.
  static const directory = 'test/fixtures/';

  static final Map<String, String> _loaded = {};

  /// Reads every world fixture [bundle] carries into memory.
  static Future<void> preload(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    for (final key in manifest.listAssets()) {
      if (key.startsWith(directory) && key.endsWith('.json')) {
        _loaded[key.substring(directory.length)] = await bundle.loadString(key);
      }
    }
  }

  /// The fixtures [preload] has read, by path under [directory].
  @visibleForTesting
  static Iterable<String> get preloaded => _loaded.keys;

  static String _read(String path) =>
      _loaded[path] ?? File('$directory$path').readAsStringSync();
}

/// The fixture at `test/fixtures/<path>`, decoded.
dynamic jsonFixture(String path) => jsonDecode(WorldFixtures._read(path));

Map<String, dynamic> jsonFixtureMap(String path) =>
    jsonFixture(path) as Map<String, dynamic>;

List<dynamic> jsonFixtureList(String path) =>
    jsonFixture(path) as List<dynamic>;

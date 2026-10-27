import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/demo/world/artwork.dart';

/// Draws the demo's pictures in a widget test straight from their asset
/// files: the image cache's own store needs `path_provider` and sqflite,
/// which a test has no plugin for. Put back when the test ends.
void useDemoArtworkFiles() {
  pinnedImageCacheBuilder =
      ({
        required cacheKey,
        required fingerprint,
        required host,
        required port,
      }) => (manager: _ArtworkFiles(), transport: _NoTransport());
  addTearDown(() {
    resetPinnedImageCaches();
    pinnedImageCacheBuilder = defaultPinnedImageCacheBuilder;
  });
}

class _ArtworkFiles implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final name = Uri.parse(url).pathSegments.lastOrNull ?? '';
    final file = const LocalFileSystem().file('${WorldArtwork.directory}$name');
    if (!file.existsSync()) throw StateError('no demo artwork at $url');
    yield FileInfo(file, FileSource.Cache, DateTime(2100), url);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

class _NoTransport implements Client {
  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

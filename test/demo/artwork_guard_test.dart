import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/artwork.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The demo's pictures: every title the Blender Studio pictures has a poster
/// and a backdrop that ship with the app, the demo names them where TMDB
/// would, and the network answers there; a world that never read them names
/// none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(WorldArtwork.forget);

  test(
    'every pictured title has a poster and a backdrop in the bundle',
    () async {
      for (final slug in WorldArtwork.slugs) {
        for (final kind in ['poster', 'backdrop']) {
          expect(
            File('${WorldArtwork.directory}$slug-$kind.jpg').existsSync(),
            isTrue,
            reason: '$slug $kind',
          );
        }
      }
      await WorldArtwork.preload(rootBundle);
      expect(WorldArtwork.files, hasLength(WorldArtwork.slugs.length * 2));
      final named = {
        for (final t in WorldTitles.catalogue)
          if (WorldArtwork.posterPath(t) != null) t.slug,
      };
      expect(named, WorldArtwork.slugs, reason: 'each picture names a title');
    },
  );

  test('a world that never read them names no picture', () {
    expect(WorldArtwork.posterPath(WorldTitles.sintel), isNull);
    expect(WorldArtwork.arrImages(WorldTitles.sintel), isEmpty);
  });

  test('the demo names a poster where TMDB would, and serves it', () async {
    await WorldArtwork.preload(rootBundle);
    final network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());
    final client = HttpClient();
    addTearDown(client.close);

    Future<HttpClientResponse> get(String url, {String? key}) async {
      final request = await client.getUrl(Uri.parse(url));
      if (key != null) request.headers.set('x-api-key', key);
      return request.close();
    }

    final detail = await get(
      '${WorldHosts.seerr}/api/v1/movie/${WorldTitles.sintel.tmdbId}',
      key: worldKey(WorldIds.seerr),
    );
    final body = jsonDecode(await detail.transform(utf8.decoder).join()) as Map;
    expect(body['posterPath'], '/sintel-poster.jpg');

    final poster = await get(
      'https://${WorldArtwork.host}/t/p/w500${body['posterPath']}',
    );
    final bytes = await poster.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(poster.statusCode, 200);
    expect(bytes.take(2), [0xFF, 0xD8], reason: 'a JPEG');
    expect(network.unanswered, isEmpty);
  });
}

/// Network artwork is decoded at the size it is drawn at, never at the
/// server's, and still fills its box: nothing looks different.
///
/// No `memCacheWidth` or `cacheWidth` existed anywhere in the app, so an arr's
/// original poster, two thousand pixels by three thousand, was decoded whole
/// for every grid tile that drew it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Client;

import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';

/// The shapes the app draws artwork in: a poster, a cover, a still.
const _shapes = {'poster': 2 / 3, 'cover': 1.0, 'still': 16 / 9};

/// What a picture of [aspect], larger than any box, decodes to under
/// [decode]: one side fixed, the other following the picture.
Size _decoded(ArtworkCacheSize decode, double aspect) {
  final width = decode.width;
  final height = decode.height;
  if (width != null) return Size(width.toDouble(), width / aspect);
  return Size(height! * aspect, height.toDouble());
}

void main() {
  group('artworkCacheSize', () {
    test('a poster tile fixes its height, at the drawn size', () {
      // A phone grid tile, about 111 by 166.5, at 3x: 499.5 pixels tall,
      // rounded up to the ladder.
      final decode = artworkCacheSize(const Size(111, 166.5), 3);

      expect(decode.width, isNull);
      expect(decode.height, 512);
      // An original poster decodes to 341 by 512, under a megabyte, where it
      // used to be 2000 by 3000 and 24 MB.
      expect(_decoded(decode, 2 / 3).width, closeTo(341.3, 0.1));
    });

    test('a wide box fixes its width', () {
      final decode = artworkCacheSize(const Size(390, 120), 3);

      expect(decode.width, 1280);
      expect(decode.height, isNull);
    });

    test('a box between a poster and a still fixes a poster\'s height', () {
      // A 64-point avatar: tall enough for a poster as wide as the box.
      final decode = artworkCacheSize(const Size.square(64), 3);

      expect(decode.width, isNull);
      expect(decode.height, 320);
    });

    test('a side the box does not fix follows the picture', () {
      expect(
        artworkCacheSize(const Size(120, double.infinity), 3),
        isA<ArtworkCacheSize>().having((d) => d.width, 'width', 384),
      );
      expect(
        artworkCacheSize(const Size(double.infinity, double.infinity), 3),
        ArtworkCacheSize.none,
      );
    });

    test('every shape the app draws still covers every box it fills', () {
      // `cover` crops what the box does not show, so the decode is only as
      // good as its smaller side: neither may fall short of the drawn box,
      // or the picture is drawn larger than it was decoded.
      for (final ratio in [1.0, 2.0, 3.0]) {
        for (var width = 18.0; width <= 1200; width *= 1.37) {
          for (var height = 18.0; height <= 1200; height *= 1.41) {
            final box = Size(width, height);
            final decode = artworkCacheSize(box, ratio);
            for (final MapEntry(key: shape, value: aspect) in _shapes.entries) {
              final decoded = _decoded(decode, aspect);
              final reason = '$shape in $box at ${ratio}x: $decoded';
              expect(
                decoded.width,
                greaterThanOrEqualTo(width * ratio - 0.5),
                reason: reason,
              );
              expect(
                decoded.height,
                greaterThanOrEqualTo(height * ratio - 0.5),
                reason: reason,
              );
            }
          }
        }
      }
    });

    test('a point more is the same decode, until a rung', () {
      expect(
        artworkCacheSize(const Size(111, 166.5), 3),
        artworkCacheSize(const Size(112, 168), 3),
      );
      var last = 0;
      for (var height = 10.0; height < 2000; height += 7) {
        final rung = artworkCacheSize(Size(height / 2, height), 1).height!;
        expect(rung, greaterThanOrEqualTo(math.min(height, 64)));
        expect(rung, greaterThanOrEqualTo(last));
        last = rung;
      }
    });
  });

  group('in the widgets', () {
    setUp(_servePending);
    tearDown(() {
      resetPinnedImageCaches();
      pinnedImageCacheBuilder = defaultPinnedImageCacheBuilder;
      CertTrustRegistry.reset();
    });

    testWidgets('a grid tile decodes at the box it fills', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 111,
              height: 166.5,
              child: ContentCard(imageUrl: _poster),
            ),
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.memCacheWidth, isNull);
      expect(image.memCacheHeight, 512);
    });

    testWidgets('a poster flies on the picture the tile already decoded, and '
        'lands on its own', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 111,
                height: 166.5,
                child: Hero(
                  tag: 'poster',
                  child: ContentCard(imageUrl: _poster),
                ),
              ),
            ),
          ),
        ),
      );

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 82,
                  height: 123,
                  child: MediaPosterCard(heroTag: 'poster', imageUrl: _poster),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mid-flight: the shuttle draws the tile's decode, 512 tall, whatever
      // size it is at this frame.
      final inFlight = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((image) => image.memCacheHeight)
          .toSet();
      expect(inFlight, contains(512));

      await tester.pumpAndSettle();
      // Landed: the poster's own decode, 123 at 3x up to the ladder.
      final landed = tester.widget<CachedNetworkImage>(
        find.descendant(
          of: find.byType(MediaPosterCard),
          matching: find.byType(CachedNetworkImage),
        ),
      );
      expect(landed.memCacheHeight, 384);
    });
  });
}

/// On an origin whose cache never answers: the picture stays loading, and
/// no test reaches a real cache.
const _poster = 'https://pending.example.com/poster.jpg';

void _servePending() {
  CertTrustRegistry.update(const {'https://pending.example.com:443': 'pin'});
  pinnedImageCacheBuilder =
      ({
        required cacheKey,
        required fingerprint,
        required host,
        required port,
      }) => (manager: _PendingCacheManager(), transport: _NoTransport());
}

class _PendingCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => StreamController<FileResponse>().stream;

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

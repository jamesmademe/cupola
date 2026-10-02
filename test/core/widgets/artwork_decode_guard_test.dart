/// Every piece of network artwork in `lib/` is decoded at the size it is drawn
/// at, through `artworkCacheSize`.
///
/// No `memCacheWidth` or `cacheWidth` existed anywhere in the app, so every
/// poster, backdrop and avatar decoded at the server's resolution: an arr's
/// original poster is two thousand pixels by three thousand, 24 MB a grid
/// tile. The regression is one new `CachedNetworkImage` that leaves the decode
/// size out and still draws, so a source scan holds it.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

void main() {
  final files = libCode();

  test('every CachedNetworkImage passes the decode size of its box', () {
    final calls = [
      for (final file in files)
        ...callsOf(file.path, file.code, RegExp(r'\bCachedNetworkImage\(')),
    ];
    expect(calls, isNotEmpty, reason: 'the scan finds the calls');

    final offenders = [
      for (final call in calls)
        if (call.named['memCacheWidth'] != 'decode.width' ||
            call.named['memCacheHeight'] != 'decode.height')
          call.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Pass `memCacheWidth: decode.width, memCacheHeight: '
          'decode.height` from an `ArtworkDecodeBox` builder '
          '(lib/core/widgets/artwork_decode.dart).',
    );
  });

  test('every CachedNetworkImageProvider is resized to its box', () {
    final opener = RegExp(r'\bCachedNetworkImageProvider\(');
    final offenders = <String>[];
    var found = 0;
    for (final file in files) {
      for (final match in opener.allMatches(file.code)) {
        found++;
        // Its own argument to `ArtworkCacheSize.resize(`, so whatever draws
        // it receives the resized provider.
        final before = file.code.substring(0, match.start).trimRight();
        if (!before.endsWith('.resize(')) {
          final line = '\n'.allMatches(before).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(found, greaterThan(0), reason: 'the scan finds the calls');
    expect(
      offenders,
      isEmpty,
      reason:
          'Wrap it: `artworkCacheSize(box, devicePixelRatio).resize('
          'CachedNetworkImageProvider(...))`.',
    );
  });
}

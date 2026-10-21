import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/code_scan.dart';

/// A group, a slab or a door is painted with **`room.door`, never
/// `room.fillQuiet`.**
///
/// The two read alike at night: the quiet fill is white at 6% over a ground of
/// `#0A0A0D`, the door `#16161C`. In the day room they part. The quiet fill is
/// the ink at 5%, a step *below* the ground, so a group drawn with it sank
/// into a grey well where the canvas lifts it onto white paper (the Stack and
/// the Media page, 21/10). The quiet fill stays what it is for: a track, a
/// segment, an empty picture, a hover.
///
/// A container is told by its radius: a group's or a slab's. A door's radius
/// is shared with the segmented tracks that rightly keep the quiet fill, so a
/// door is held by review, not here. A source scan, because the regression is
/// one plausible word in a diff.
final _container = RegExp(r'AppRadius\.(group|slab|borderRadiusSlab)\b');

void main() {
  final files = libCode();

  test('lib/ has code to scan', () {
    expect(files.length, greaterThan(300));
  });

  test('no group or slab is painted with the quiet fill', () {
    final offenders = [
      for (final file in files)
        for (final call in callsOf(
          file.path,
          file.code,
          RegExp(r'\bBoxDecoration\('),
        ))
          if (call.named['color'] == 'room.fillQuiet' &&
              _container.hasMatch(call.named['borderRadius'] ?? ''))
            call.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A group, slab or door is painted with room.door: white in the day '
          'room, a step above the ground at night. room.fillQuiet is a step '
          'below the ground in the day room.',
    );
  });
}

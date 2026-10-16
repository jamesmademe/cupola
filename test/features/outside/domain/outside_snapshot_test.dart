import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/outside/domain/outside_snapshot.dart';

/// The file the widgets draw from: its frames and its shape.
void main() {
  // Friday 16 October 2026, 14:02.
  final takenAt = DateTime(2026, 10, 16, 14, 2);

  OutsideFace face(String age) => OutsideFace(title: 'Downloads', age: age);

  group('frames', () {
    test('the first is the read, the rest in time order', () {
      final frames = outsideFramesAt(takenAt, [
        takenAt.add(const Duration(hours: 2)),
        takenAt.add(const Duration(hours: 1)),
      ], (at) => face('${at.hour}'));
      expect(frames.map((frame) => frame.from), [
        takenAt,
        takenAt.add(const Duration(hours: 1)),
        takenAt.add(const Duration(hours: 2)),
      ]);
    });

    test(
      'a moment before the read, or one that changes nothing, is no frame',
      () {
        final frames = outsideFramesAt(
          takenAt,
          [
            takenAt.subtract(const Duration(hours: 1)),
            takenAt.add(const Duration(minutes: 5)),
            takenAt.add(const Duration(hours: 1)),
          ],
          (at) => face(
            at.isBefore(takenAt.add(const Duration(hours: 1)))
                ? 'fresh'
                : 'old',
          ),
        );
        expect(frames.map((frame) => frame.face.age), ['fresh', 'old']);
      },
    );

    test('a widget keeps at most a dozen', () {
      final frames = outsideFramesAt(takenAt, [
        for (var hour = 1; hour < 40; hour++)
          takenAt.add(Duration(hours: hour)),
      ], (at) => face(at.toIso8601String()));
      expect(frames, hasLength(OutsideSnapshot.maxFrames));
    });

    test('the midnights are local and come after the read', () {
      expect(outsideMidnights(takenAt), [
        DateTime(2026, 10, 17),
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 19),
      ]);
    });
  });

  test('the file says its version, in instants, and leaves out what is not '
      'there', () {
    final snapshot = OutsideSnapshot(
      takenAt: takenAt,
      audience: 'operator',
      frames: {
        OutsideWidget.downloads: [
          OutsideFrame(
            takenAt,
            const OutsideFace(
              title: 'Downloads',
              age: 'As of 14:02',
              items: [
                OutsideItem(
                  title: 'Charge',
                  words: 'Stuck at 12%',
                  tone: OutsideTone.amber,
                  progress: 0.12,
                ),
              ],
            ),
          ),
        ],
      },
    );
    final json = snapshot.toJson();
    expect(json['version'], 1);
    expect(json['takenAt'], takenAt.toUtc().toIso8601String());
    final frame = (json['widgets'] as Map)['downloads'][0] as Map;
    expect(frame['from'], takenAt.toUtc().toIso8601String());
    expect(frame['face'], {
      'title': 'Downloads',
      'items': [
        {
          'title': 'Charge',
          'words': 'Stuck at 12%',
          'tone': 'amber',
          'progress': 0.12,
        },
      ],
      'age': 'As of 14:02',
      'aged': false,
    });
  });

  test('red is not a tone a widget has', () {
    expect(OutsideTone.values.map((tone) => tone.name), [
      'green',
      'amber',
      'blue',
      'neutral',
    ]);
  });
}

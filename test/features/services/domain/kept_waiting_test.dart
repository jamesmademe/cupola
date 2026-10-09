import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/kept_waiting.dart';

void main() {
  final now = DateTime(2026, 10, 9, 20, 53);

  test('a day from the choice, at the share that had arrived', () {
    final choice = KeptWaiting.from(now: now, progress: 0.47);
    expect(choice.until, DateTime(2026, 10, 10, 20, 53));
    expect(choice.progress, 0.47);
  });

  test('holds while nothing arrives, until its day is up', () {
    final choice = KeptWaiting.from(now: now, progress: 0.47);
    expect(
      choice.holds(
        currentProgress: 0.47,
        now: now.add(const Duration(hours: 23)),
      ),
      isTrue,
    );
    expect(
      choice.holds(currentProgress: 0.47, now: now.add(keptWaitingFor)),
      isFalse,
    );
  });

  test('lapses as soon as the download moves; rounding is not '
      'moving', () {
    final choice = KeptWaiting.from(now: now, progress: 0.47);
    expect(choice.holds(currentProgress: 0.4705, now: now), isTrue);
    expect(choice.holds(currentProgress: 0.49, now: now), isFalse);
  });

  test('round-trips its wire form, and ignores anything else', () {
    final choice = KeptWaiting.from(now: now, progress: 0.47);
    expect(KeptWaiting.fromJson(choice.toJson()), choice);
    expect(KeptWaiting.fromJson('2026-10-10'), isNull);
    expect(KeptWaiting.fromJson({'until': 'tomorrow', 'progress': 1}), isNull);
  });
}

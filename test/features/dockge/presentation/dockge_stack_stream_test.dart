import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/presentation/dockge_provider.dart';

/// Real time at a small scale: `limit` stands for Dockge's ten seconds.
void main() {
  const limit = Duration(milliseconds: 40);
  Object timeout() => StateError('no first event');
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  test(
    'a gap longer than the limit after the first event is not an error',
    () async {
      // Dockge re-pushes its stack list on a ten-second cron. A push a little
      // late must not end a stream that has already answered — which is what
      // `Stream.timeout`, measuring every gap, did.
      final source = StreamController<int>.broadcast();
      final events = <int>[];
      final errors = <Object>[];
      final sub = firstEventWithin(
        source.stream,
        limit,
        timeout,
      ).listen(events.add, onError: errors.add);

      await wait(5);
      source.add(1);
      await wait(120);
      source.add(2);
      await wait(5);

      expect(events, [1, 2]);
      expect(errors, isEmpty);
      await sub.cancel();
      await source.close();
    },
  );

  test(
    'no first event within the limit is an error, and ends the stream',
    () async {
      final source = StreamController<int>.broadcast();
      final errors = <Object>[];
      var done = false;
      firstEventWithin(
        source.stream,
        limit,
        timeout,
      ).listen((_) {}, onError: errors.add, onDone: () => done = true);

      await wait(120);

      expect(errors.single, isA<StateError>());
      expect(done, isTrue);
      expect(source.hasListener, isFalse);
      await source.close();
    },
  );

  test('the clock stops while paused', () async {
    // Riverpod pauses a provider nobody on screen watches; the answer sits in
    // the paused subscription's buffer and must not be failed from there.
    final source = StreamController<int>.broadcast();
    final events = <int>[];
    final errors = <Object>[];
    final sub = firstEventWithin(
      source.stream,
      limit,
      timeout,
    ).listen(events.add, onError: errors.add);

    sub.pause();
    await wait(120);
    expect(errors, isEmpty);

    sub.resume();
    await wait(5);
    source.add(7);
    await wait(5);

    expect(events, [7]);
    expect(errors, isEmpty);
    await sub.cancel();
    await source.close();
  });
}

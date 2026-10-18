/// A long-lived socket nothing uses is let go after a while, and never while
/// a call is out or somebody listens to what it pushes.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/idle_close.dart';

void main() {
  const after = Duration(milliseconds: 80);
  Future<void> wait([Duration d = const Duration(milliseconds: 160)]) =>
      Future<void>.delayed(d);

  test('closes once nothing has used it for the while', () async {
    var closed = 0;
    final idle = IdleClose(after: after, onIdle: () => closed++)..settle();
    addTearDown(idle.dispose);

    await wait();
    expect(closed, 1);
  });

  test('never while a call is out, and waits again from its end', () async {
    var closed = 0;
    final idle = IdleClose(after: after, onIdle: () => closed++);
    addTearDown(idle.dispose);

    idle.begin();
    await wait();
    expect(closed, 0, reason: 'a call is in flight');

    idle.end();
    await wait(const Duration(milliseconds: 40));
    expect(closed, 0, reason: 'the while has not passed since it ended');
    await wait();
    expect(closed, 1);
  });

  test('never while somebody listens, and waits again once they go', () async {
    var closed = 0;
    var listening = true;
    final idle = IdleClose(
      after: after,
      quiet: () => !listening,
      onIdle: () => closed++,
    );
    addTearDown(idle.dispose);

    idle.settle();
    await wait();
    expect(closed, 0);

    listening = false;
    idle.settle();
    await wait();
    expect(closed, 1);
  });

  test('a listener arriving during the wait keeps it open', () async {
    var closed = 0;
    var listening = false;
    final idle = IdleClose(
      after: after,
      quiet: () => !listening,
      onIdle: () => closed++,
    )..settle();
    addTearDown(idle.dispose);

    listening = true;
    idle.hold();
    await wait();
    expect(closed, 0);
  });

  test('nothing after dispose', () async {
    var closed = 0;
    IdleClose(after: after, onIdle: () => closed++)
      ..settle()
      ..dispose();

    await wait();
    expect(closed, 0);
  });
}

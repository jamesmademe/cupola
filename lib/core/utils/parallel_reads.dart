import 'dart:async';

/// Two reads started together, awaited in order.
///
/// The failure is the read's own error, raised by the first await that meets
/// it, as when the reads ran one after the other. `(a, b).wait` would throw a
/// `ParallelWaitError` instead, which a caller reading the error's type sees
/// as something else. The no-op listeners keep a failure of the read awaited
/// second from being reported as unhandled while the first is being awaited.
Future<(A, B)> readTogether<A, B>(Future<A> first, Future<B> second) async {
  unawaited(first.then<void>((_) {}, onError: (_) {}));
  unawaited(second.then<void>((_) {}, onError: (_) {}));
  return (await first, await second);
}

/// [readTogether] for three reads, awaited in order.
Future<(A, B, C)> readTogether3<A, B, C>(
  Future<A> first,
  Future<B> second,
  Future<C> third,
) async {
  unawaited(first.then<void>((_) {}, onError: (_) {}));
  unawaited(second.then<void>((_) {}, onError: (_) {}));
  unawaited(third.then<void>((_) {}, onError: (_) {}));
  return (await first, await second, await third);
}

/// [count] tasks, at most [lanes] of them running at once, answered in task
/// order whichever finished first.
///
/// For reads that are independent and many (the pages of a list, the titles of
/// a history), where starting them all together would open one socket each on
/// a server that is a NAS. A lane takes the next index when it is free, so a
/// slow task holds up one lane and not a whole batch. [task] must not throw:
/// a lane that threw would stop taking work and leave its results unread, so a
/// caller that can fail returns its failure as a value.
Future<List<R>> runInLanes<R>(
  int count,
  int lanes,
  Future<R> Function(int index) task,
) async {
  final results = List<R?>.filled(count, null);
  var next = 0;

  Future<void> lane() async {
    while (true) {
      final index = next++;
      if (index >= count) return;
      results[index] = await task(index);
    }
  }

  await Future.wait([
    for (var i = 0; i < (lanes < count ? lanes : count); i++) lane(),
  ]);
  return [for (final result in results) result as R];
}

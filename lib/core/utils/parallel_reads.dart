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

import 'package:cupola/core/network/connection_failure.dart';

/// Retry policy for providers whose failure something else is waiting to read.
///
/// ## What Riverpod does by default
///
/// `ProviderContainer.defaultRetry` re-runs a build that throws up to **ten**
/// times, backing off exponentially from 200ms to a 6.4s ceiling. It skips
/// `Error` and `ProviderException`, but a `DioException` is an `Exception`, so
/// every network failure in this app is retried. The provider does not settle
/// until that sequence ends: roughly forty seconds of backoff, plus ten round
/// trips of whatever the request's own timeout is.
///
/// ## When that is wrong
///
/// For a provider a widget watches, it is usually right: the widget shows its
/// loading state and a blip heals itself.
///
/// It is wrong wherever another provider does `await ref.watch(x.future)`
/// **inside a `try` that exists to degrade or to report**, because the `catch`
/// cannot run until the retries are exhausted. The handler's whole purpose is
/// to keep going without this source, and it is held for forty seconds instead.
/// A sequential loop over several sources multiplies that by the number of them
/// that are down.
///
/// Retrying is the user's call in those places: every surface that reads one
/// offers a Retry, and the polled ones come back on their own tick.
///
/// ## Where this is used, and where it is deliberately not
///
/// The rule, not a list (a list here went stale as every service adopted it):
/// a provider that reads a service carries it, and so does every provider
/// derived from one, or it waits out its source's retries. That covers each
/// service's own providers (the \*arrs, Seerr, Prowlarr, Bazarr, the download
/// clients, the media servers, TrueNAS, Unraid, Dockge, NPM) and the KPI reads
/// behind the rail, which are awaited inside a `catch` that turns a failure
/// into an em dash and would otherwise wait out ten backed-off attempts first.
///
/// Deliberately **not** applied to the `/services` dashboard's summary, queue
/// and recently-added providers. Their `settle()` looks like the same shape,
/// but each one already catches its own failures and degrades to an offline
/// summary or an empty list, so they never throw and the retry never
/// engages.
///
/// ## The one failure it retries at once
///
/// A read whose client was closed under it ([isClosedClientFailure]) is
/// asked again straight away: the connection's settings changed, its client
/// provider closed the client the read was holding, and the rebuilt one is a
/// read away. Nothing about the server is known from it, and the user has
/// nothing to retry. Bounded, because only a connection that keeps changing
/// could close the next client too.
Duration? noProviderRetry(int retryCount, Object error) =>
    retryCount < _closedClientRetries && isClosedClientFailure(error)
    ? Duration.zero
    : null;

/// How many times in a row a read caught by a closing client is asked again.
const _closedClientRetries = 3;

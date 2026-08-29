/// Retry policy for providers whose failure something else is waiting to read.
///
/// ## What Riverpod does by default
///
/// `ProviderContainer.defaultRetry` re-runs a build that throws up to **ten**
/// times, backing off exponentially from 200ms to a 6.4s ceiling. It skips
/// `Error` and `ProviderException` — but a `DioException` is an `Exception`, so
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
/// **inside a `try` that exists to degrade or to report** — because the `catch`
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
/// Applied to the Seerr request providers and to the Jellyfin and Plex session
/// providers — the sources read that way today.
///
/// Deliberately **not** applied to:
///
/// * the `/services` dashboard's summary, queue and recently-added providers.
///   Their `settle()` looks like the same shape, but each one already catches
///   its own failures and degrades to an offline summary or an empty list, so
///   they never throw and the retry never engages.
/// * Prowlarr's derived providers and the service KPIs. They await `.future`
///   without a `try`, so the error propagates to a screen that renders it —
///   there a retry only delays an error rather than hiding a recovery.
Duration? noProviderRetry(int retryCount, Object error) => null;

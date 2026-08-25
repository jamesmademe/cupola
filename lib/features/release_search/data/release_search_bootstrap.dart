import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import 'package:cupola/features/release_search/data/background_task_hygiene.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';

/// Prepares the background transport, and cleans up after the last session.
///
/// **Runs unconditionally, including for a user who has background search
/// switched off, and that is the whole point.** Two of the three things here are
/// hygiene rather than capability: `start()` is what pops the records the plugin
/// left in iOS preferences and Android preferences when the Dart side was not
/// alive to receive them, and [BackgroundTaskHygiene.pruneFinishedWork] is what
/// drops WorkManager's stored copy of finished jobs. Skip them for the user who
/// opted out and the setting becomes a privacy regression: the last search they
/// ran before switching it off would keep its API key on disk indefinitely.
///
/// The gate for the feature lives one layer up, on the reach that decides which
/// transport a search gets — see `releaseSearchTransportProvider`. Nothing here
/// enqueues anything.
///
/// Three library defaults are actively wrong for a release search:
///
/// **`requestTimeout`** defaults to 60 seconds and measures the gap *between
/// received bytes* — and this request is the pathological case, because the
/// server sends nothing while it queries indexers. Left alone, every search over
/// a minute would fail on iOS. It can only be set **once, before the first task
/// is enqueued**, which is why it lives at startup rather than beside the
/// setting it relates to: the library's ceiling is infrastructure, and the
/// user's own timeout always sits below it.
///
/// **`resourceTimeout`** is the only ceiling that still applies while the app is
/// suspended, when no Dart timer can fire — so it is what actually bounds the
/// life of a task whose headers carry the service's API key, and the plugin
/// keeps that task record in plaintext until it reaches a final state. An hour
/// let a credential-bearing task outlive the user's own ceiling by ~50 minutes
/// for no benefit: nothing here ever downloads a large file, only a JSON release
/// list. It is set to the longest search the settings screen permits plus a
/// grace, so the backstop sits just above the user's maximum instead of far
/// beyond it.
///
/// **`doRescheduleKilledTasks`** would silently re-issue a task the OS killed —
/// re-running a full search against the user's indexers with nobody watching. A
/// killed search surfaces as a state to retry by hand instead.
///
/// Every seam is injectable because this function is the one place those three
/// defaults are decided, and a test that cannot observe them cannot defend them.
Future<void> configureBackgroundSearch({
  bool Function()? supported,
  // `Config.requestTimeout` and friends are plain string keys, and the
  // plugin's own parameter is `dynamic` — typed here so a wrong pair is a
  // compile error rather than a platform-channel surprise.
  Future<void> Function(List<(String, Object)> globalConfig)? configure,
  Future<void> Function({required bool doRescheduleKilledTasks})? start,
  Future<bool> Function()? prune,
}) async {
  if (!(supported ?? backgroundSearchSupported)()) return;

  // Ordered: the plugin has to exist before it can be asked to clean up, but a
  // failure in either half must not cost the other. A platform without the
  // plugin still runs the foreground path, which is the whole point of keeping
  // the transport behind an interface.
  try {
    await (configure ?? _configureViaPlugin)([
      (Config.requestTimeout, const Duration(minutes: 15)),
      (Config.resourceTimeout, kBackgroundSearchResourceTimeout),
    ]);
    await (start ?? _startViaPlugin)(doRescheduleKilledTasks: false);
  } catch (_) {
    // Nothing to configure; the foreground transport needs none of it.
  }

  // Unawaited on purpose: this is housekeeping about the *last* session, and
  // nothing at this launch waits on it. Its own failures are already swallowed.
  unawaited((prune ?? _pruneViaChannel)());
}

Future<void> _configureViaPlugin(List<(String, Object)> globalConfig) =>
    FileDownloader().configure(globalConfig: globalConfig);

Future<void> _startViaPlugin({required bool doRescheduleKilledTasks}) =>
    FileDownloader().start(doRescheduleKilledTasks: doRescheduleKilledTasks);

Future<bool> _pruneViaChannel() =>
    const BackgroundTaskHygiene().pruneFinishedWork();

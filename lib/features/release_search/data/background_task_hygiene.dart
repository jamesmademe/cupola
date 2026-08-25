import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Clears what the OS still holds about background searches that have finished.
///
/// One method, one platform, one reason: on Android a `DataTask` runs through
/// WorkManager, so the request — headers, and therefore the arr admin API key —
/// is stored as the job's `inputData` in WorkManager's database. That row
/// survives the search by design: the automatic pruning has a one-day threshold
/// and runs only when the database is next opened, and the downloader plugin
/// never prunes at all. Asking for a prune at launch is what turns "at least a
/// day, eventually" into "until the next launch".
///
/// iOS needs no counterpart. Its two records — the task in `nsurlsessiond` and
/// the fallback status map in preferences — are cleared by the plugin itself:
/// the task at any final state, the map by `FileDownloader().start()`, which
/// `configureBackgroundSearch` calls at every launch. The asymmetry is the
/// plugin's, not ours.
///
/// Deliberately **not** gated on whether the user has background search
/// switched on. The records this clears are the ones a *previous* session left
/// behind, so gating it would mean the user who switches the feature off keeps
/// the last copy of their key for as long as the OS feels like it — the setting
/// would read as privacy and behave as the opposite.
class BackgroundTaskHygiene {
  const BackgroundTaskHygiene({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  static const _channelName = 'com.matthwlabs.cupola/background_task_hygiene';

  /// Asks WorkManager to drop its records of finished jobs.
  ///
  /// Returns whether the platform says it did. Best-effort by contract, and the
  /// failure modes are all benign: on any platform but Android there is nothing
  /// to prune, and on Android the channel is unanswered whenever the process was
  /// started by WorkManager itself rather than by the user — no Activity, so no
  /// handler. Nothing is lost in that case, because the launch that does have a
  /// UI prunes the same records.
  Future<bool> pruneFinishedWork() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('pruneFinishedWork') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

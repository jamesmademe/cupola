import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/release_search/data/background_task_hygiene.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';

/// Injected so a test can watch the prune happen without a platform channel.
final backgroundTaskHygieneProvider = Provider(
  (ref) => const BackgroundTaskHygiene(),
);

/// Flipping background search on or off, with everything that has to happen
/// around it.
///
/// A separate object rather than an `onChanged` closure because **switching off
/// is a sequence and the order carries the promise**. The copy beside the switch
/// says turning it off clears the stored records; that is only true if the
/// searches in flight are cancelled *first*:
///
/// 1. **Cancel every active search.** On the native transport a cancelled task
///    reaches a final state, and a final state is the condition under which the
///    plugin deletes its own record, the one holding the API key. A search left
///    to drain keeps that record until it ends on its own.
/// 2. **Then persist the flag.** After this the reach resolves to
///    `whileOpenSwitchedOff` and nothing new can be handed to the OS.
/// 3. **Then prune.** The records cancelled in step 1 have just become
///    prunable, so WorkManager's copy goes too, now rather than at the next
///    launch.
///
/// Doing 2 before 1 would be the subtle bug: the jobs would still be cancelled,
/// but a `_pump()` racing the flag could start a queued search on the transport
/// the user just switched off.
class BackgroundSearchSwitch {
  const BackgroundSearchSwitch(this._ref);

  final Ref _ref;

  /// What the cancelled jobs say. Named constants because a test asserting on
  /// the verdict should not be asserting on a string literal typed twice.
  static const cancelHeadline = 'Canceled, background search was turned off.';
  static const cancelDiagnosis =
      'Searches in flight were stopped so nothing of theirs stays on the '
      'device. Searching again keeps this one in the app.';

  Future<void> set(bool enabled) async {
    if (enabled) {
      // Nothing to clean up on the way in, and nothing to ask: the OS wants no
      // permission for a background task. The next search simply gets the
      // native transport.
      _ref
          .read(releaseSearchSettingsProvider.notifier)
          .setBackgroundEnabled(true);
      return;
    }

    _ref
        .read(releaseSearchJobsProvider.notifier)
        .cancelAll(headline: cancelHeadline, diagnosis: cancelDiagnosis);
    _ref
        .read(releaseSearchSettingsProvider.notifier)
        .setBackgroundEnabled(false);
    await _ref.read(backgroundTaskHygieneProvider).pruneFinishedWork();
  }
}

final backgroundSearchSwitchProvider = Provider(BackgroundSearchSwitch.new);

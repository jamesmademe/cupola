import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The write actions the Activity surfaces can perform on a queue or blocklist
/// record.
///
/// Activity was a read-only feed: it could tell you a download had stalled and
/// then offered no way to do anything about it, so the resolution path for every
/// problem it surfaced was to leave and open the service's web UI. These close
/// that loop.
///
/// Each one confirms first — neutrally, with a verb that says what will happen,
/// never in red, which means unreachable and nothing else — reports the outcome, and bumps [activityRefreshVersionProvider] so every
/// bucket re-reads rather than leaving a removed row on screen.
///
/// ## Every write takes the connection it acts on
///
/// These used to resolve the service through the **lens** — whichever Radarr
/// the user last looked at. That was correct only while the feed showed one
/// server. Now that /activity merges every connection, the lens and the row are
/// different facts, and \*arr record ids are per server: each one numbers its
/// queue from one, so `id: 7` names a different download on each Sonarr.
/// Sending a removal to the lens would delete somebody else's download and
/// report success. So the caller passes the row's own `instanceId` and it
/// resolves through [connectionArrServiceProvider]; an empty id still means
/// "the lens", which is what the per-service Activity screen wants.
///
/// The same is true of the two request actions, for the same reason in Seerr's
/// vocabulary: a request id is per instance, so approving id 42 through the
/// lens approves a different person's request on a different server — and
/// reports success. They resolve through `seerrServiceForProvider`.
class ActivityActions {
  ActivityActions._();

  /// Removes a queue record, optionally blocklisting the release.
  ///
  /// The two toggles are the two decisions the \*arr API actually exposes, and
  /// they mean different things: deleting from the client frees the disk,
  /// blocklisting stops the same release being grabbed again on the next search.
  /// Blocklisting alone is the "this release is bad, find another" move.
  static Future<void> removeFromQueue(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from queue?',
      message: title,
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'Remove and delete files',
      // The button names both decisions as they stand, so what it says is what
      // the tap sends.
      confirmLabelFor: (checked) =>
          switch ((checked('removeFromClient'), checked('blocklist'))) {
            (true, true) => 'Remove, delete files and blocklist',
            (true, false) => 'Remove and delete files',
            (false, true) => 'Remove and blocklist',
            (false, false) => 'Remove from queue',
          },
      options: const [
        AppConfirmOption(
          key: 'removeFromClient',
          label: 'Delete from download client',
          subtitle:
              'Also removes the files that have been downloaded so far. This '
              'cannot be undone.',
          initialValue: true,
        ),
        AppConfirmOption(
          key: 'blocklist',
          label: 'Blocklist this release',
          subtitle: 'Stops it being grabbed again, so a search finds another.',
        ),
      ],
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => ref
          .read(connectionArrServiceProvider((serviceType, instanceId)))
          .removeFromQueue(
            recordId,
            removeFromClient: result.option('removeFromClient'),
            blocklist: result.option('blocklist'),
          ),
      successMessage: result.option('blocklist')
          ? 'Removed and blocklisted'
          : 'Removed from queue',
      failureMessage: 'Could not remove from queue',
    );
  }

  /// Blocklists the current release and immediately searches for another.
  ///
  /// This is what a user means by "retry": the \*arr API has no retry endpoint,
  /// so the equivalent is to reject what is there and go looking again.
  static Future<void> blocklistAndRetry(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Blocklist and search?',
      message:
          '$title will be removed and blocklisted, then a new search runs for '
          'a different release.',
      icon: Icons.refresh_rounded,
      confirmLabel: 'Blocklist and search',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => ref
          .read(connectionArrServiceProvider((serviceType, instanceId)))
          .removeFromQueue(recordId, removeFromClient: true, blocklist: true),
      successMessage: 'Blocklisted, searching for another release',
      failureMessage: 'Could not blocklist this release',
    );
  }

  /// Removes a release from the blocklist so it can be grabbed again.
  static Future<void> removeFromBlocklist(
    BuildContext context,
    WidgetRef ref, {
    required ServiceType serviceType,
    required String instanceId,
    required int recordId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove from blocklist?',
      message: '$title becomes eligible to be grabbed again.',
      icon: Icons.playlist_add_check_rounded,
      confirmLabel: 'Remove from blocklist',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: serviceType.service,
      action: () => ref
          .read(connectionArrServiceProvider((serviceType, instanceId)))
          .deleteBlocklistItem(recordId),
      successMessage: 'Removed from blocklist',
      failureMessage: 'Could not remove from blocklist',
    );
  }

  /// Approves a request that is waiting on somebody.
  ///
  /// This closes the loop the screen has always half-shown: `resolveRequestStatus`
  /// already tones a pending request `warning` precisely to say it needs a
  /// person, and until now the only way to be that person was to leave for the
  /// Seerr web UI.
  static Future<void> approveRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Approve this request?',
      message:
          '$title goes to the service that handles it and starts downloading.',
      icon: Icons.check_circle_outline_rounded,
      confirmLabel: 'Approve request',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: ServiceKey.seerr,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .approveRequest(requestId),
      successMessage: 'Request approved',
      failureMessage: 'Could not approve this request',
      invalidateRequests: true,
    );
  }

  /// Declines a request, leaving the media alone.
  static Future<void> declineRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline this request?',
      message:
          '$title will not be downloaded. The request stays on record as '
          'declined.',
      icon: Icons.cancel_outlined,
      confirmLabel: 'Decline request',
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;

    await _run(
      context,
      ref,
      service: ServiceKey.seerr,
      action: () => ref
          .read(seerrServiceForProvider(instanceId))
          .declineRequest(requestId),
      successMessage: 'Request declined',
      failureMessage: 'Could not decline this request',
      invalidateRequests: true,
    );
  }

  /// Runs a mutation, reports it, and refreshes the feed.
  ///
  /// The failure message names what did not happen rather than echoing a Dio
  /// exception: `'Search failed: $error'` was the previous house style and it
  /// surfaced transport internals to someone who wanted to know whether their
  /// download was gone.
  static Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required ServiceKey service,
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,

    /// Seerr requests arrive through a separately cached provider, so bumping
    /// the feed version alone re-runs the merge over the same stale list. The
    /// whole family goes, not just the acted-on connection: the lens's own
    /// entry collapses onto the plain provider, so the two have to be dropped
    /// together or the feed re-reads one of them stale.
    bool invalidateRequests = false,
  }) async {
    try {
      await action();
      if (context.mounted) SnackBarHelper.success(context, successMessage);
    } on SeerrRequestConflict catch (conflict) {
      // Deliberately not a `return`: the action did not fail, it was overtaken.
      // The stale thing is the list on screen, so this falls through to the
      // refresh below instead of leaving a row the server no longer agrees with.
      if (context.mounted) SnackBarHelper.error(context, '$conflict');
    } catch (error) {
      // Why, in the classified words: a refusal is not an outage, and the
      // toast used to guess "may be unreachable" for both.
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          '$failureMessage. ${writeFailureReason(service, error)}',
        );
      }
      return;
    }

    if (invalidateRequests) {
      ref.invalidate(requestsProvider);
      ref.invalidate(requestsForProvider);
    }
    ref.read(activityRefreshVersionProvider.notifier).state++;
  }
}

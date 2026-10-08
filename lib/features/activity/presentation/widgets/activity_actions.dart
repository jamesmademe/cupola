import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_approve_target_read.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
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
      title: 'Try another download?',
      message:
          '$title will be removed and never picked again, then a new search '
          'looks for a different release.',
      icon: Icons.refresh_rounded,
      confirmLabel: 'Try another download',
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
      successMessage: 'Looking for another download',
      failureMessage: 'Could not try another download',
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
  ///
  /// The confirmation says where the request goes ([SeerrApproveTarget]): the
  /// server by name, and in one clause when Cupola has no connection to it.
  /// It used to say "the service that handles it" whichever that was, a 4K
  /// server and one known only to Seerr included. [request] is the record
  /// when the caller holds it; otherwise it is read from Seerr by
  /// [requestId] first.
  ///
  /// Answers what a row may say once it went through (`Approved · sent to
  /// Radarr`), or null when it did not: refused, overtaken or cancelled.
  static Future<String?> approveRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
    SeerrRequest? request,
  }) async {
    if (!_decides(context, ref, instanceId)) return null;
    // Captured before any wait: the approval outlives the control that
    // started it, and the notifier is the container's, not the widget's.
    final approvals = ref.read(seerrApprovalsInFlightProvider.notifier);
    final key = (instanceId: instanceId, requestId: requestId);
    // A second tap while the first is still being read or sent does nothing.
    var owned = approvals.begin(key, SeerrApprovalPhase.checking);
    if (!owned) return null;
    try {
      final (:message, :approved) = await _approveConfirmation(
        ref,
        instanceId: instanceId,
        requestId: requestId,
        title: title,
        request: request,
      );
      // Idle behind the dialog, which is modal: the control is not busy
      // while a person decides.
      approvals.end(key);
      owned = false;
      if (!context.mounted) return null;

      final result = await showAppConfirmDialog(
        context: context,
        title: 'Approve this request?',
        message: message,
        icon: Icons.check_circle_outline_rounded,
        confirmLabel: 'Approve request',
      );

      if (!result.confirmed) return null;
      if (!context.mounted) return null;
      owned = approvals.begin(key, SeerrApprovalPhase.approving);
      if (!owned) return null;

      final done = await _run(
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
      return done ? approved : null;
    } finally {
      // Only an approval this call still holds: never another tap's.
      if (owned) approvals.end(key);
    }
  }

  /// Whether the Seerr [instanceId] names lets this app decide on its
  /// requests, said on a toast when it does not: the account may not approve
  /// there. Every Approve and Decline in the app comes through here, so a
  /// control drawn before the account's permissions changed cannot send a
  /// decision the server would refuse.
  static bool _decides(BuildContext context, WidgetRef ref, String instanceId) {
    final verdict = ref
        .read(roleGateProvider(instanceId))
        .operatorAction(SeerrAbility.approve);
    if (verdict.acts) return true;
    final reason = verdict.reason;
    if (reason != null) SnackBarHelper.info(context, reason);
    return false;
  }

  /// What the approve confirmation says, read within one
  /// [seerrTargetReadLimit] ([readSeerrApproveTarget]), and what the row
  /// says once it is approved.
  static Future<({String message, String approved})> _approveConfirmation(
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
    required SeerrRequest? request,
  }) async {
    final settings = ref.read(currentSettingsProvider);
    final read = await readSeerrApproveTarget(
      ref,
      instanceId: instanceId,
      requestId: requestId,
      request: request,
    );
    final target = read.target;
    if (target == null) {
      // Not even its kind is known: the approval still goes where Seerr
      // sends it, and that is all that can be said.
      return (
        message:
            '$title goes to the server Seerr sends it to and starts '
            'downloading.',
        approved: 'Approved',
      );
    }
    String connectionTitle(ServiceInstance connection) => settings
        .connectionTitle(connection.id, connection.service, joiner: ' ');
    return (
      message: target.confirmation(title, connectionTitle: connectionTitle),
      approved: target.approvedLine(connectionTitle: connectionTitle),
    );
  }

  /// Declines a request, leaving the media alone. True when it went
  /// through.
  static Future<bool> declineRequest(
    BuildContext context,
    WidgetRef ref, {
    required String instanceId,
    required int requestId,
    required String title,
  }) async {
    if (!_decides(context, ref, instanceId)) return false;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Decline this request?',
      message:
          '$title will not be downloaded. The request stays on record as '
          'declined.',
      icon: Icons.cancel_outlined,
      confirmLabel: 'Decline request',
    );

    if (!result.confirmed) return false;
    if (!context.mounted) return false;

    return _run(
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
  static Future<bool> _run(
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
      _refresh(ref, invalidateRequests: invalidateRequests);
      return false;
    } catch (error) {
      // Why, in the classified words: a refusal is not an outage, and the
      // toast used to guess "may be unreachable" for both.
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          '$failureMessage. ${writeFailureReason(service, error)}',
          cause: error,
        );
      }
      return false;
    }
    _refresh(ref, invalidateRequests: invalidateRequests);
    return true;
  }

  /// Every list the write may have changed, read again.
  static void _refresh(WidgetRef ref, {required bool invalidateRequests}) {
    if (invalidateRequests) {
      ref.invalidate(requestsProvider);
      ref.invalidate(requestsForProvider);
      ref.invalidate(activeRequestsForProvider);
      ref.invalidate(pendingRequestsForProvider);
    }
    ref.read(activityRefreshVersionProvider.notifier).state++;
  }
}

/// One approval, named by the Seerr it is sent to and the request's id there.
typedef SeerrApprovalKey = ({String instanceId, int requestId});

/// Where an approval is between its tap and its answer.
enum SeerrApprovalPhase {
  /// Reading where the request goes, before the confirmation opens.
  checking('Checking where it goes'),

  /// The approval itself, sent and not yet answered.
  approving('Approving');

  const SeerrApprovalPhase(this.spoken);

  /// What a screen reader hears of the busy control.
  final String spoken;
}

/// The approvals in flight, and how far each has got.
///
/// What makes the tapped control busy at once, and a second tap a no-op: an
/// approval used to read for up to eight seconds with nothing on screen, and
/// every tap meanwhile started another read and, in the end, another
/// confirmation.
class SeerrApprovalsInFlight
    extends Notifier<Map<SeerrApprovalKey, SeerrApprovalPhase>> {
  @override
  Map<SeerrApprovalKey, SeerrApprovalPhase> build() => const {};

  /// Marks [key] as at [phase]. False, and nothing changes, when it is
  /// already in flight.
  bool begin(SeerrApprovalKey key, SeerrApprovalPhase phase) {
    if (state.containsKey(key)) return false;
    state = {...state, key: phase};
    return true;
  }

  /// Marks [key] as done. Safe to call when it is not in flight.
  void end(SeerrApprovalKey key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final seerrApprovalsInFlightProvider =
    NotifierProvider<
      SeerrApprovalsInFlight,
      Map<SeerrApprovalKey, SeerrApprovalPhase>
    >(SeerrApprovalsInFlight.new);

/// An Approve control's glyph: [idle], or while the approval of
/// [requestId] on [instanceId] is in flight, a ring in the same ink and at
/// the same [size], so the control keeps its target and its place.
///
/// The ring carries the phase as the control's value, `Checking where it
/// goes` or `Approving`: annotated here, inside the button, because a
/// `Semantics` wrapped around a button lands on a node the screen reader
/// never focuses.
class SeerrApprovalGlyph extends ConsumerWidget {
  const SeerrApprovalGlyph({
    super.key,
    required this.instanceId,
    required this.requestId,
    required this.size,
    required this.idle,
  });

  final String instanceId;
  final int requestId;
  final double size;
  final Widget idle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      seerrApprovalsInFlightProvider.select(
        (inFlight) => inFlight[(instanceId: instanceId, requestId: requestId)],
      ),
    );
    if (phase == null) return idle;
    return Semantics(
      value: phase.spoken,
      child: SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size / 8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: IconTheme.of(context).color,
          ),
        ),
      ),
    );
  }
}

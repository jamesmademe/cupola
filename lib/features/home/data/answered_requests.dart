/// The requests answered since the Home was last read: each says what
/// happened, in place of its Approve and Decline, until the Home is read
/// again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';

/// A request answered here, and what its row says now: `Approved · sent to
/// Radarr`, `Declined`.
///
/// [decision] is the Home's row for it, kept so the Requests module goes on
/// drawing the answered row once Seerr's list no longer holds the request.
/// Null for a request answered from anywhere else (the Activity feed, a
/// requests list, a title's page), which has no Home row to keep.
typedef AnsweredRequest = ({DashboardDecision? decision, String outcome});

/// What names a request across every list that draws it: the Seerr it lives
/// on and its id there. The same string a Home row's
/// [DashboardDecision.id] carries, so the Home and the control answer the
/// same question with the same key.
///
/// [instanceId] is empty for the lens's own Seerr.
String seerrRequestKey(String instanceId, int requestId) =>
    'seerr-$instanceId-$requestId';

/// The answered requests, by [seerrRequestKey].
///
/// Without it an approved row vanished as Seerr's list was read again, and
/// nothing said where the request went. Emptied when the Home is read
/// again (pull, return, the tab tapped twice): by then the rows that still
/// wait are the ones on screen.
class AnsweredRequests extends Notifier<Map<String, AnsweredRequest>> {
  @override
  Map<String, AnsweredRequest> build() => const {};

  /// Records that the request [requestId] of the Seerr [instanceId] was
  /// answered, and says [outcome] in place of its controls.
  void answer({
    required String instanceId,
    required int requestId,
    required String outcome,
    DashboardDecision? decision,
  }) {
    state = {
      ...state,
      seerrRequestKey(instanceId, requestId): (
        decision: decision,
        outcome: outcome,
      ),
    };
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

final answeredRequestsProvider =
    NotifierProvider<AnsweredRequests, Map<String, AnsweredRequest>>(
      AnsweredRequests.new,
    );

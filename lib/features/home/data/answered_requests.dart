/// The requests answered from the Home since it was last read: each keeps
/// its row, saying what happened, until the Home is read again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';

/// A request answered here, and what its row says now: `Approved · sent to
/// Radarr`, `Declined`.
typedef AnsweredRequest = ({DashboardDecision decision, String outcome});

/// The answered requests, by decision id.
///
/// Without it an approved row vanished as Seerr's list was read again, and
/// nothing said where the request went. Emptied when the Home is read
/// again (pull, return, the tab tapped twice): by then the rows that still
/// wait are the ones on screen.
class AnsweredRequests extends Notifier<Map<String, AnsweredRequest>> {
  @override
  Map<String, AnsweredRequest> build() => const {};

  void answer(DashboardDecision decision, String outcome) {
    state = {...state, decision.id: (decision: decision, outcome: outcome)};
  }

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

final answeredRequestsProvider =
    NotifierProvider<AnsweredRequests, Map<String, AnsweredRequest>>(
      AnsweredRequests.new,
    );

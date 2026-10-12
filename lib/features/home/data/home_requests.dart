/// What the Home's Requests module reads: the requests waiting for the
/// operator, and Seerr's own count of them, as one read.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// The requests that wait, and how many there are.
///
/// [counted] is what Seerr says it holds across every connection that may be
/// answered ([pendingRequestCountProvider]), never the length of the page the
/// rows came from; null while that read is out and when a Seerr did not give
/// it, which the module then counts from its rows. [settled] says no read of
/// the two is still out: a figure read while one is would be the rows' length
/// said as a total.
typedef HomeRequests = ({
  List<DashboardDecision> decisions,
  SourceCoverage coverage,
  ({int count, bool floor})? counted,
  bool settled,
});

/// The rows of the requests that wait, with Seerr's count of them.
///
/// The rows arrive first and are drawn at once, as they always were: the count
/// is read beside them, and is [HomeRequests.counted] once it is there. A
/// refresh of either keeps the last answer while it is out, like the reads it
/// is made of.
///
/// A request answered on the Home in this run is not among the rows, though
/// Seerr's list may still hold it until it is read again: what is kept as the
/// last drawing is made of this, and an answered request is not waiting.
final homeRequestsProvider = Provider<AsyncValue<HomeRequests>>((ref) {
  final rows = ref.watch(
    dashboardDecisionSourceProvider(DecisionSource.requests),
  );
  final value = rows.value;
  if (value == null) {
    final error = rows.error;
    return error == null
        ? const AsyncLoading()
        : AsyncError(error, rows.stackTrace ?? StackTrace.empty);
  }
  final count = ref.watch(pendingRequestCountProvider);
  final answered = ref.watch(answeredRequestsProvider);
  return AsyncData((
    decisions: [
      for (final decision in value.decisions)
        if (!answered.containsKey(decision.id)) decision,
    ],
    coverage: value.coverage,
    counted: count.value,
    settled: !rows.isLoading && !count.isLoading,
  ));
});

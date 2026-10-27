import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/silence_age.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/list_rows_shimmer.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a download client's queue page knows about itself before it draws a
/// row: the same five readings for SABnzbd, NZBGet and Transmission.
///
/// - [failed]: a failed probe in its own words ("did not answer" only when
///   nothing did, the refusal and its remedy when the sign-in was refused), or
///   the list's own failure band until the probe says it.
/// - [silentFor]: how long the connection has not answered, said only when
///   that is what the probe found: a fault is an answer, and carries no span.
/// - [staleAge]: with no fault band, a read that stopped coming back says so
///   (`FaultBand.stale`); a fault band, which says why, wins.
/// - [sampleAge]: how old the rows are, only while they are the last read
///   under a band: their figures stopped moving when the client stopped
///   answering, or when its read stopped coming back.
/// - [list]: what the rows draw, the last read kept under a band, and what a
///   header counts: the same `when` the rows draw with, so a header never
///   counts a list its section is not showing.
///
/// With nothing to keep ([offline]) the failure is the page; over a list
/// already read it is a band and the list stays under it as it was last said.
typedef ClientQueueFrame<T> = ({
  ServiceSummary? failed,
  Duration? silentFor,
  Duration? staleAge,
  Duration? sampleAge,
  AsyncValue<T> list,
  bool offline,
});

/// Reads [watched] (the client's queue, watched by the caller) and the probe of
/// [service] into a [ClientQueueFrame]. Called from the page's build, with its
/// [context] and [ref], after `watchWhileLive`.
ClientQueueFrame<T> watchClientQueueFrame<T>(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  AsyncValue<T> watched,
) {
  final failed = clientPageFailure(
    service,
    summary: ref.watch(serviceSummaryProvider(service)),
    list: watched,
  );
  final silentFor = ref.watchSilence(
    context,
    service,
    silent: failed?.didNotAnswer ?? false,
  );
  final offline = failed != null && !watched.hasValue;
  final list = lastReadUnderBand(watched, banded: failed != null);
  final staleAge = ref.watchQueueStaleAge(
    context,
    service,
    underBand: failed != null,
    hasQueue: watched.hasValue,
  );
  final sampleAge = ref.watchQueueReadAge(
    context,
    service,
    underBand: failed != null || staleAge != null,
  );
  return (
    failed: failed,
    silentFor: silentFor,
    staleAge: staleAge,
    sampleAge: sampleAge,
    list: list,
    offline: offline,
  );
}

/// One section of a download client's queue, as a sliver: every row, lazily
/// built, with the loading, failure and empty states drawn once per section.
///
/// [rowsOf] is the section's slice of what [value] loaded (the whole list, or
/// one of Transmission's two halves of it); [rowBuilder] draws one. A failure
/// is one `InlineErrorRetry` line in the section's slot, [consequence] saying
/// what is not shown, and [onRetry] asking again.
Widget clientRowsSliver<T, R>({
  required ServiceKey service,
  required AsyncValue<T> value,
  required List<R> Function(T data) rowsOf,
  required String emptyTitle,
  required Widget Function(BuildContext context, R row) rowBuilder,
  required String consequence,
  required VoidCallback onRetry,
}) {
  return value.when(
    data: (data) {
      final rows = rowsOf(data);
      if (rows.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppEmptyState.inline(
              icon: Icons.download_done_rounded,
              title: emptyTitle,
            ),
          ),
        );
      }
      return SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) => rowBuilder(context, rows[index]),
      );
    },
    loading: () => const SliverToBoxAdapter(child: ListRowsShimmer()),
    error: (error, _) => SliverToBoxAdapter(
      child: InlineErrorRetry(
        message: sectionFailureMessage(
          service,
          error,
          consequence: consequence,
        ),
        error: error,
        service: service,
        onRetry: onRetry,
      ),
    ),
  );
}

/// Your requests: what the requester asked for that is still on its way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/my_requests_last_known.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/requests/presentation/my_request_actions.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// The most rows the module shows; the rest are on her page.
const yourRequestsLimit = 3;

/// What she asked for that is still on its way, with the one thing she
/// wants to know of each: when. `62%`, `Ready around 21:10`; `On its way`
/// when Seerr sees no download it can measure; `Waiting for approval`; an
/// answer of the last seven days, `Declined`, neutral. Never amber: a stuck
/// download is the operator's fault, and to her it is on its way.
///
/// With nothing on its way, a calm line points to Discover. When the server
/// does not answer the Home's one line says so and the rows stay, read as
/// they were and without a figure that no longer moves.
///
/// At a cold start the rows are the last drawing's until her Seerr answers
/// (`watchMyRequestsOrLastKnown`), read the same way: no percentage and no
/// `Ready around 21:10`, since a drawing does not run, so a download reads
/// `On its way`. A drawing with nothing left to list is the skeleton, never
/// `Nothing on its way`, which is a claim about now.
class HomeYourRequestsModule extends ConsumerWidget {
  const HomeYourRequestsModule({super.key});

  static final _title = HomeModule.yourRequests.label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:read, :asOf) = ref.watchMyRequestsOrLastKnown();
    final mine = read.requests;
    if (mine == null) {
      return read.error != null
          ? const SizedBox.shrink()
          : HomeModuleFrame.loading(title: _title);
    }
    final now = ref.watch(calendarClockProvider)();
    final rows = mine.homeRows(now);
    final coming = mine.onTheWay.length;
    final subtitle = switch (coming) {
      0 => null,
      1 => '1 on its way',
      _ => '$coming on the way',
    };
    if (rows.isEmpty) {
      if (asOf != null) {
        // Nothing left of a drawing is not "nothing on its way": the
        // skeleton, as before an answer, and nothing under a failure the
        // page already says.
        return read.error == null
            ? HomeModuleFrame.loading(title: _title)
            : const SizedBox.shrink();
      }
      return HomeModuleFrame(
        title: _title,
        semanticLabel: joinSpokenParts([_title, 'Nothing on its way']),
        child: const _NothingOnItsWay(),
      );
    }
    final shown = rows.take(yourRequestsLimit).toList(growable: false);
    return LastKnownMark(
      asOf: asOf,
      checking: read.error == null,
      child: HomeModuleFrame(
        title: _title,
        subtitle: subtitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, row) in shown.indexed)
              RequesterRequestRow.home(
                key: ValueKey(row.request.id),
                mine: row,
                now: now,
                divided: index > 0,
                onTap: () => openMyRequest(context, row),
              ),
            HomeModuleLink(
              label: 'All your requests',
              onTap: () => context.go(ServiceRoutes.requests),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing on its way: a check, the line, and Discover.
class _NothingOnItsWay extends StatelessWidget {
  const _NothingOnItsWay();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: room.inkSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nothing on its way',
                        style: AppType.row.copyWith(color: room.ink),
                      ),
                      Text(
                        'Find something to ask for in Discover.',
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => context.go(ServiceRoutes.discover),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: const Size(0, 44),
            ),
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('Discover'),
          ),
        ],
      ),
    );
  }
}

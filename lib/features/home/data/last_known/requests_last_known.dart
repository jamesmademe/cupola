/// Requests' last drawing: the requests that waited for the operator, and the
/// count the line under the heading said.
library;

import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/home_requests.dart';
import 'package:cupola/features/home/data/last_known/dashboard_decision_codec.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';

/// How many rows the drawing keeps: the most the module shows (a wide desktop
/// takes four) and a margin.
const _kept = 8;

/// The waiting requests as the live read had them, oldest first and capped,
/// with the count Seerr gave and whether it was a floor (`50+`).
///
/// The count is the one the line said, kept with the rows and said again as it
/// was: it is never made out of the rows here, which hold a page of the
/// requests and not all of them. So a read is kept only whole: every Seerr
/// answered and the count is in. One that is partial would draw a figure that
/// reads as a total and cannot carry the note that says who is missing from
/// it, and one still out would draw the rows' length; the drawing before such
/// a read is the better one. A read with nothing waiting is kept, empty, so
/// that a request answered since is not drawn again.
///
/// The requests answered on the Home in this run are not part of it: they are
/// the module's own, and the live list no longer holds them.
final requestsLastKnown = HomeLastKnownSlot<HomeRequests>(
  id: 'requests',
  schema: 1,
  services: HomeModule.requests.services.toSet(),
  encode: (read) {
    final counted = read.counted;
    if (!read.settled || counted == null) return null;
    if (read.coverage.failed.isNotEmpty || read.coverage.pending.isNotEmpty) {
      return null;
    }
    return {
      'count': counted.count,
      'floor': counted.floor,
      'rows': [
        for (final decision in rankDecisions(read.decisions, cap: _kept))
          ?dashboardDecisionToJson(decision),
      ],
    };
  },
  decode: (data, _) {
    if (data is! Map) return null;
    final count = data['count'];
    final floor = data['floor'];
    final rows = data['rows'];
    if (count is! int || floor is! bool || rows is! List) return null;
    final read = [for (final json in rows) dashboardDecisionFromJson(json)];
    if (read.contains(null)) return null;
    return (
      decisions: [for (final decision in read) decision!],
      coverage: SourceCoverage.none,
      counted: (count: count, floor: floor),
      settled: true,
    );
  },
);

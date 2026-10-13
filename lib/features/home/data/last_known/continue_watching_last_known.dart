/// Continue watching's last drawing: the titles somebody started and did not
/// finish, and which Jellyfin was waiting to be told who "you" are.
library;

import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/resume_row_codec.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';

/// How many rows the drawing keeps: the module draws three, and a margin for
/// the one that Featured leads with.
const _kept = continueWatchingRowLimit * 2;

/// The rows as the live read had them, capped, and the connections that were
/// asking who you are.
///
/// Where somebody stopped is a fact as of then, not a figure that runs, so
/// the bar and the time left are drawn as they were; the row's own words are
/// made of them again. Not kept when every server was silent: the drawing
/// before is the better one. Kept when nothing was in progress and every
/// server answered, as an empty drawing, so that what somebody has finished
/// since is not drawn again.
///
/// Which Jellyfin is asking who you are is a fact of the settings, not of any
/// answer, and the drawing is valid only for the viewers it was made under,
/// so it is kept to spare the module a question that appears a second late.
final continueWatchingLastKnown = HomeLastKnownSlot<HomeResume>(
  id: 'continue-watching',
  schema: 1,
  services: HomeModule.continueWatching.services.toSet(),
  encode: (resume, _) {
    if (resume.coverage.everySourceFailed) return null;
    return {
      'rows': [for (final row in resume.rows.take(_kept)) resumeRowToJson(row)],
      'viewerMissing': resume.viewerMissing,
    };
  },
  silent: (resume) => resume.coverage.everySourceFailed,
  decode: (data, _) {
    if (data is! Map) return null;
    final rows = data['rows'];
    final missing = data['viewerMissing'];
    if (rows is! List || missing is! List) return null;
    final read = [for (final json in rows) resumeRowFromJson(json)];
    if (read.contains(null) || missing.any((id) => id is! String)) return null;
    return (
      rows: [for (final row in read) row!],
      coverage: SourceCoverage.none,
      viewerMissing: [for (final id in missing) id as String],
    );
  },
);

/// Arrived's last drawing: the imports of the week, newest first.
library;

import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/arr_history_entry_codec.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// How many imports the drawing keeps: the rail's cards and a margin for
/// the ones a day's turn drops out of the week.
const _kept = 24;

/// The imports only, newest first and capped: the failures in the same read
/// are Needs you's, which never draws from a last drawing (P-t1-no-faults).
/// The week is cut again when it is drawn (`arrivedOf` with that day's
/// `since`), so a card that turned eight days old in between is gone.
///
/// Not kept when every library was silent: the drawing before is better.
final arrivedLastKnown = HomeLastKnownSlot<ArrHistory>(
  id: 'arrived',
  schema: 1,
  services: HomeModule.arrived.services.toSet(),
  encode: (history) {
    if (history.coverage.everySourceFailed) return null;
    final imports = [
      for (final entry in history.entries)
        if (entry.outcome == ArrImportOutcome.imported && entry.at != null)
          entry,
    ]..sort((a, b) => b.at!.compareTo(a.at!));
    return {
      'entries': [
        for (final entry in imports.take(_kept)) arrHistoryEntryToJson(entry),
      ],
    };
  },
  decode: (data, _) {
    if (data is! Map || data['entries'] is! List) return null;
    return (
      entries: [
        for (final json in data['entries'] as List)
          ?arrHistoryEntryFromJson(json),
      ],
      coverage: SourceCoverage.none,
    );
  },
);

/// Downloads' last drawing: the rows it drew and the counts it stated.
///
/// This is the module where a drawing can lie most, so what it keeps is
/// narrow, and what it draws from it is narrower:
///
///  * **Figures that run are not kept.** No time left, no transfer rate, no
///    stall clock (`serviceQueueItemToJson`). A row's progress is the
///    position the bar was at, and is drawn as a bar that stopped (neutral),
///    never as one that moves.
///  * **No fault is kept.** A download that was stuck is kept as the
///    download it was: it is judged stuck by the live read and by the stall
///    clock, the choices of the day and the actions taken, and by nothing
///    older. The footnote about blocked imports is Needs you's own count and
///    is not kept either.
///  * **A count is kept only for a whole read.** With a queue that did not
///    answer, or that stopped short, the rows are what was seen and the
///    counts are not stated, and `Nothing is downloading` is never said.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/service_queue_item_codec.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// What Downloads draws of a read: its first rows (the moving ones, then the
/// stuck ones, as [downloadRowsOf] orders them), the counts it states, and
/// whether every queue answered whole when it was read.
///
/// The rows of a live drawing are the live items; the rows of a last one have
/// gone through the codec, which keeps no fault and nothing that runs.
typedef DownloadsDrawing = ({
  List<ServiceQueueItem> rows,
  int moving,
  int queued,
  bool whole,
});

/// [data] as Downloads draws it: nothing at all of a read no queue answered.
DownloadsDrawing downloadsDrawingOf(ServicesInFlight data) {
  final coverage = data.coverage;
  return (
    rows: coverage.everySourceFailed
        ? const <ServiceQueueItem>[]
        : downloadRowsOf(data.preview, [
            for (final item in data.faults)
              if (isDownloadFault(item.fault)) item,
          ]),
    moving: data.movingCount,
    queued: data.queued.length,
    whole: coverage.isWhole,
  );
}

/// The live read as a drawing, for `watchOrLastKnown` to keep: the same
/// answer as [servicesInFlightProvider], and a failure as a failure. Read
/// through `servicesInFlightProvider.select`, so the module holds one provider
/// and not two that depend on each other.
AsyncValue<DownloadsDrawing> downloadsDrawingRead(
  AsyncValue<ServicesInFlight> read,
) {
  final value = read.value;
  if (value != null) return AsyncData(downloadsDrawingOf(value));
  if (read.hasError) {
    return AsyncError(read.error!, read.stackTrace ?? StackTrace.empty);
  }
  return const AsyncLoading();
}

/// The drawing of a read that answered whole, with no row, says nothing is
/// downloading, and is only kept for that. A read that was cut, or that some
/// queue did not answer, with no row to show is not worth keeping: the drawing
/// before it is the better one.
///
/// What a drawing's `Nothing is downloading` was true of is exactly that read:
/// the module draws it only while no import is known to have finished after
/// it (`downloads_module.dart`).
final downloadsLastKnown = HomeLastKnownSlot<DownloadsDrawing>(
  id: 'downloads',
  schema: 1,
  services: HomeModule.downloads.services.toSet(),
  encode: (drawing) {
    if (drawing.rows.isEmpty && !drawing.whole) return null;
    return {
      'whole': drawing.whole,
      if (drawing.whole) ...{
        'moving': drawing.moving,
        'queued': drawing.queued,
      },
      'rows': [
        for (final row in drawing.rows.take(downloadsRowLimit))
          serviceQueueItemToJson(row),
      ],
    };
  },
  decode: (data, image) {
    if (data is! Map || data['rows'] is! List || data['whole'] is! bool) {
      return null;
    }
    final whole = data['whole'] as bool;
    final rows = [
      for (final json in (data['rows'] as List).take(downloadsRowLimit + 1))
        serviceQueueItemFromJson(json, image),
    ];
    // A row this version cannot read whole is no row: and a drawing missing
    // one would count and say `Nothing is downloading` over it.
    if (rows.length > downloadsRowLimit || rows.contains(null)) return null;
    final moving = whole ? _count(data['moving']) : 0;
    final queued = whole ? _count(data['queued']) : 0;
    if (moving == null || queued == null) return null;
    if (rows.isEmpty && !whole) return null;
    if (rows.isEmpty && moving > 0) return null;
    return (
      rows: [for (final row in rows) row!],
      moving: moving,
      queued: queued,
      whole: whole,
    );
  },
);

int? _count(Object? value) => switch (value) {
  final int count when count >= 0 => count,
  _ => null,
};

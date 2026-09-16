/// The grammar of the Dashboard's fifth region: what is moving, right now.
///
/// ## Why the row is one mono line and not four fields
///
/// The region this replaces printed a title, a `·`-joined subtitle assembled by
/// each source in its own words, and a percentage — so a Radarr row said
/// `Radarr · Movie · Bluray-2160p · Dune.Part.Two…` and a SABnzbd row said
/// `SABnzbd · movies · 1.2 GB`, and the two could not be read down a column.
/// The four facts a transfer actually has are the same for every client:
///
///     quality · done of total · time left · client
///
/// Quality drops out when the source has none (a download client knows the file
/// size, not the release's quality profile); everything else is always present
/// or explicitly absent. Absent prints `—`, **never `0`**: a figure nobody was
/// able to take is not zero, and `0 B` would say the transfer has not started.
///
/// Set in `TextStyle.mono.tabular` by the row, which is why the parts are
/// formatted to a fixed shape here rather than left to each service's own
/// formatter.
library;

import 'package:cupola/core/utils/byte_format.dart';

/// The em dash every absent figure in this region prints.
///
/// One constant so a second call site cannot invent a hyphen, an empty string or
/// a zero. See the library doc for why it is not `0`.
const String kAbsentFigure = '—';

/// `14.0 of 15.2 GB` — two sizes on one unit, or `—` when either is unknown.
///
/// Rendered on the **total's** unit deliberately. Formatted independently, a
/// transfer 900 MB into a 15.2 GB file reads `900.0 MB of 15.2 GB`, which asks
/// the reader to convert before they can see it is nowhere near done. One unit
/// makes the pair comparable at a glance, which is the only reason both numbers
/// are on the row.
String formatDoneOfTotal({int? doneBytes, int? totalBytes}) {
  if (totalBytes == null || totalBytes <= 0) return kAbsentFigure;
  if (doneBytes == null || doneBytes < 0) return kAbsentFigure;

  final total = formatBytesPrecise(totalBytes);
  final unit = total.split(' ').last;
  final divisor = _divisorFor(unit);
  if (divisor == null) return '$doneBytes of $total';

  final done = doneBytes / divisor;
  // One decimal on the done side, always: it is the half that moves, and a
  // figure that changes its own width as it counts jitters even in tabular
  // digits. `B` is the exception — bytes are whole things.
  final text = unit == 'B' ? doneBytes.toString() : done.toStringAsFixed(1);
  return '$text of $total';
}

double? _divisorFor(String unit) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final index = units.indexOf(unit);
  if (index < 0) return null;
  var divisor = 1.0;
  for (var i = 0; i < index; i++) {
    divisor *= 1024;
  }
  return divisor;
}

/// `3 min left`, `2 h 10 min left`, `48 s left` — or `—` when nobody knows.
///
/// Never seconds above a minute, and never a bare number: "3" in a row of
/// figures is not a duration. qBittorrent reports 8 640 000 for "no estimate",
/// which is filtered by the caller rather than printed as a hundred days.
String formatTimeLeft(int? seconds) {
  if (seconds == null || seconds < 0) return kAbsentFigure;
  if (seconds < 60) return '$seconds s left';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min left';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours < 24) {
    return rest == 0 ? '$hours h left' : '$hours h $rest min left';
  }
  final days = hours ~/ 24;
  return '$days d left';
}

/// The whole row line: `2160p · 14.0 of 15.2 GB · 3 min left · qBittorrent`.
///
/// The client is last and always present — it is the answer to "where do I go to
/// touch this", and it is the one part of the line a merged region cannot leave
/// to a glyph.
String formatInFlightLine({
  String? quality,
  int? doneBytes,
  int? totalBytes,
  int? etaSeconds,
  required String client,
}) {
  final parts = <String>[
    if (quality != null && quality.trim().isNotEmpty) quality.trim(),
    formatDoneOfTotal(doneBytes: doneBytes, totalBytes: totalBytes),
    formatTimeLeft(etaSeconds),
    client,
  ];
  return parts.join(' · ');
}

/// The region's eyebrow: `2 downloading · 15.5 MB/s across 2 clients`.
///
/// The rate is summed **per client and only per client** — a byte rate is a
/// countable unit, so it adds up, but only over sources that actually reported
/// one. An \*arr does not report a rate for its own queue (the bytes are moving
/// through a download client, which is reporting them already), so counting it
/// as zero would drag the average down and counting it as missing would make the
/// aggregate partial. Neither: it is not a rate source, and [clients] counts the
/// ones that are.
String inFlightEyebrow({
  required int active,
  required int? rateBytesPerSecond,
  required int clients,
}) {
  final counted = '$active downloading';
  if (rateBytesPerSecond == null || clients <= 0) return counted;
  final noun = clients == 1 ? 'client' : 'clients';
  return '$counted · ${formatBytesPerSecond(rateBytesPerSecond)} '
      'across $clients $noun';
}

/// The footnote under the region when stalls were moved out of it.
///
/// The region shows active transfers only; a stalled one is a decision, not a
/// transfer, and it lives in the region above. Saying so is what stops the
/// count here disagreeing with the client's own queue depth without explanation.
String? inFlightStalledFootnote(int stalled) {
  if (stalled <= 0) return null;
  final noun = stalled == 1 ? 'stall' : 'stalls';
  return stalled == 1
      ? '1 stalled · under a decision above'
      : '$stalled $noun · under decisions above';
}

/// What one in-flight row announces after its title.
///
/// The visible line is `·`-joined for the eye; `·` is decoration a screen reader
/// reads as "middle dot" or drops, so the ear gets the same facts with the comma
/// both readers treat as a short pause.
String inFlightRowValue({required String line, required int? percent}) => [
  if (percent != null) '$percent% done',
  ...line.split('·').map((part) => part.trim()).where((p) => p.isNotEmpty),
].join(', ');

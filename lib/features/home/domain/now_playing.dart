/// The words of the Home's Now playing module: who is watching what, on
/// which screen, and how long is left.
///
/// No transcode detail and no bitrate: what a playback costs the server is
/// the media server's page's business. The bar is ink, since watching is not
/// a status.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

/// How many sessions the module draws before the way to the server's page.
const nowPlayingRowLimit = 4;

final _episodeCode = RegExp(r'^S\d+ E\d+(?:–E?\d+)?');

/// `Anna · Sintel`, `Anna · Cosmos Laundromat · S2 E3`: who, and what. The
/// episode's code and not its name, which the series page has.
String nowPlayingTitle(StreamSession session) {
  final code = _episodeCode.stringMatch(session.subtitle ?? '');
  final who = session.userName.trim();
  return [if (who.isNotEmpty) who, session.title, ?code].join(dotSeparator);
}

/// `Living room TV · 9 min left`, with `Stopped` before the time while the
/// player holds it: where, and how long is left. Nothing about when it
/// started, which no server says.
String nowPlayingLine(StreamSession session) {
  final remaining = session.remaining;
  return [
    if (session.deviceLabel.trim().isNotEmpty) session.deviceLabel.trim(),
    if (session.isPaused) StateWord.stopped.label,
    if (remaining != null) '${formatTimeSpan(remaining)} left',
  ].join(dotSeparator);
}

/// The initial on the row's disc: the first letter of who is watching.
String nowPlayingInitial(StreamSession session) {
  final who = session.userName.trim();
  return who.isEmpty ? '?' : String.fromCharCode(who.runes.first).toUpperCase();
}

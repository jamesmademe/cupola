/// qBittorrent's tracker status codes in the app's five tones.
///
/// It lives here rather than beside the dot that draws it for the reason every
/// other tone rule in this app is a top-level pure function: it is a *reading*
/// of a field, it is the kind of thing that goes quietly wrong, and a switch
/// buried in a private widget is a switch no test can reach.
///
/// The detail screen's dot painted `AppColors.success` and `AppColors.warning`
/// straight from the palette — skipping the contrast walk every other mark goes
/// through — and gave code `4` the theme's `error` red. Both are the same two
/// mistakes `_toneFor` in `presentation/widgets/torrent_tile.dart` was written
/// to undo for the ten torrent states.
library;

import 'package:cupola/core/status/media_status.dart';

/// How a tracker's status code reads on the five-arm tone rule.
///
///  * **green** for `2` (*Working*) — the announce landed and the tracker is
///    answering, which is the only code that means "this one is fine".
///  * **blue** for `3` (*Updating*) — an announce in flight is work in
///    progress. Amber here would flag every tracker on every torrent for the
///    second or two each announce takes.
///  * **amber** for `4` (*Not working*) — a **fault**, and deliberately not
///    red. Red in this app claims the client never replied, and qB was alive
///    enough to tell us the tracker is down; it is the same reading a stalled
///    torrent gets one tab away.
///  * **neutral** for `0` (*Disabled*), `1` (*Not contacted*) and any code this
///    app has no name for — backlog and the resting state of a torrent that has
///    not announced yet. An unknown code is not evidence of anything, so it
///    never falls through to green.
StatusTone trackerStatusTone(int status) => switch (status) {
  2 => StatusTone.success,
  3 => StatusTone.info,
  4 => StatusTone.warning,
  _ => StatusTone.neutral,
};

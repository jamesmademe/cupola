import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// A Transmission torrent, on the app's one queue plate.
///
/// This was the **last** private copy of [DownloadQueueTile]: qBittorrent's went
/// this morning, SABnzbd's and NZBGet's before it. What it carried that the
/// plate now carries for every client — its own radius and 11px padding, a
/// hand-rolled `LinearProgressIndicator`, a percentage painted from
/// `AppColors.transmission`, a warning line painted from `AppColors.warning` —
/// was not Transmission's; it was four clients' worth of the same row drifting
/// apart. What genuinely is Transmission's is below: the daemon's own status
/// vocabulary, the stall/error phrase it reports, the two rates, the ratio, and
/// the per-torrent command menu no other client here has.
///
/// The three things the design lets a client differ in are exactly the three
/// used: the label chip, the metrics and the menu.
class TransmissionTorrentTile extends StatelessWidget {
  const TransmissionTorrentTile({
    super.key,
    required this.torrent,
    this.actions,
  });

  final TransmissionTorrent torrent;

  /// The row's trailing ⋯.
  ///
  /// A slot rather than a menu built here, for the reason the plate takes one:
  /// the commands dispatch through the screen's `ref`, and a tile that reached
  /// for a provider would be a screen again. Transmission is the one client on
  /// this plate that has per-torrent commands wired, and they sit behind a 44pt
  /// trailing target rather than a long-press — a menu reachable only by
  /// long-press is a menu a pointer user and a switch user cannot reach at all.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    // The daemon's own sentence when it has one — "Stalled", or the error string
    // it reported — and its plain status otherwise. It used to be printed as a
    // coloured prefix glued onto the front of the subtitle, which is the same
    // fact in a place where nothing could read it as a state.
    final warning = torrent.warning;
    final incoming = torrent.status.isIncoming;

    return DownloadQueueTile(
      title: torrent.name,
      // One figure, chosen by direction. While bytes are coming in, what is
      // left is the fact that changes; once the torrent is seeding or stopped
      // there is nothing left to arrive and the ratio is what the user is
      // actually watching. The rates moved to the metric row and the status to
      // the chip, so this line no longer repeats either.
      subtitle: incoming
          ? torrent.remainingLabel
          : 'Ratio ${torrent.ratioLabel}',
      progress: _drawsBar ? torrent.progress : null,
      percentage: (torrent.progress * 100).round(),
      accent: ServiceKey.transmission.accent,
      statusLabel: warning ?? torrent.status.label,
      statusTone: _tone,
      metrics: [
        if (torrent.rateDownload > 0)
          DownloadQueueMetric(
            label: '↓ ${torrent.downloadSpeedLabel}',
            accented: true,
            // The arrow carries the whole meaning and screen readers disagree
            // about it — some skip it, some name the character. Spelt out, it
            // is a sentence.
            spoken: 'downloading at ${torrent.downloadSpeedLabel}',
          ),
        if (torrent.rateUpload > 0)
          DownloadQueueMetric(
            label: '↑ ${torrent.uploadSpeedLabel}',
            spoken: 'uploading at ${torrent.uploadSpeedLabel}',
          ),
      ],
      actions: actions,
      // No tap and no long-press on purpose: this dashboard has no torrent
      // detail page to open and no multi-select, and a row that highlights and
      // goes nowhere is worse than one that does not invite the press. The
      // plate omits its InkWell — and its inner semantics node — when both are
      // null, so the row stays one thing a screen reader can act on.
    );
  }

  /// Whether this torrent has a transfer worth drawing a bar for.
  ///
  /// A finished torrent has none — it is seeding, and a full bar under a seeding
  /// row reads as "finishing" about something that finished. Nor does one that
  /// is only queued, or one the daemon has stopped with an error: a 0% bar under
  /// either says "stuck" about a transfer that has not begun. A *stopped*
  /// torrent keeps its bar, because where it got to is the thing the user
  /// stopped it at.
  bool get _drawsBar =>
      torrent.progress < 1 &&
      !torrent.errorKind.isBlocking &&
      torrent.status != TransmissionStatus.downloadWait &&
      torrent.status != TransmissionStatus.seedWait &&
      torrent.status != TransmissionStatus.checkWait;

  /// Transmission's eight states in the app's five tones.
  ///
  /// The private row had no state chip at all: it printed the status as prose
  /// and coloured only the *warning* case, in `AppColors.warning` straight from
  /// the palette. Through [StatusTone] the same five arms apply here as
  /// everywhere else:
  ///
  ///  * **amber** for anything [TransmissionTorrent.warning] names — a stall or
  ///    a daemon-reported error. Both are faults: the client answered, and what
  ///    it answered is that this torrent is stuck. Red would claim it never
  ///    replied.
  ///  * **green** for seeding, the one state that means "this one is done";
  ///  * **blue** for a live download or a running check, which is work in
  ///    flight;
  ///  * **neutral** for stopped and for the three queues — backlog and
  ///    deliberate stops are the resting state of a torrent client and must not
  ///    compete with the states that are actually wrong.
  StatusTone get _tone {
    if (torrent.warning != null) return StatusTone.warning;
    return switch (torrent.status) {
      TransmissionStatus.seed => StatusTone.success,
      TransmissionStatus.download ||
      TransmissionStatus.check => StatusTone.info,
      TransmissionStatus.stopped ||
      TransmissionStatus.downloadWait ||
      TransmissionStatus.seedWait ||
      TransmissionStatus.checkWait ||
      TransmissionStatus.unknown => StatusTone.neutral,
    };
  }
}

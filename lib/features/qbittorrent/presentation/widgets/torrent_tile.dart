import 'package:flutter/material.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A torrent, on the app's one queue plate.
///
/// This used to be a full second implementation of [DownloadQueueTile]: 267
/// lines with its own radius, padding, leading glyph tile, state chip, progress
/// bar and speed labels, which is the exact duplication the shared widget was
/// written to prevent, and it had already drifted in the ways duplicates do: no
/// semantics container at all (a screen reader walked a torrent as four unlabelled
/// fragments), a state chip painted from raw `AppColors` constants that measure
/// between 1.4:1 and 2.1:1 on the light theme, and its own `AppRadius`/`Border`
/// spelling that no longer matched the two Usenet dashboards.
///
/// What is left is the mapping, which is the only part that was ever
/// qBittorrent's: field names, the state vocabulary, and the two transfer rates.
/// Three things differ between clients on this plate: the label chip, the
/// metrics and the menu items, and all three of qBittorrent's are below.
class TorrentTile extends StatelessWidget {
  final Torrent torrent;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The row's trailing ⋯, when the host supplies one.
  ///
  /// A slot rather than a menu built here: decision 28 puts the per-torrent
  /// commands behind a 44pt trailing target and leaves long-press to selection,
  /// and the commands themselves need the screen's `ref` to dispatch. Nothing
  /// passes it yet: the qBittorrent screen still reaches its commands through
  /// the detail page's Actions tab, so the slot exists and stays empty rather
  /// than the plate growing a menu it cannot wire.
  final Widget? actions;

  const TorrentTile({
    super.key,
    required this.torrent,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final state = torrent.parsedState;
    final eta = torrent.etaFormatted;

    return DownloadQueueTile(
      title: torrent.name,
      // What the old row put on its second line, in the plate's own order. The
      // ETA only when there is one: qB answers 8640000 seconds for "never",
      // which `etaFormatted` renders `∞` for the detail page, and that is
      // every seeding torrent. Beside a size it read as a figure about the
      // size, and a screen reader said "infinity".
      subtitle: <String>[
        torrent.sizeFormatted,
        if (eta.isNotEmpty && eta != '∞') eta,
      ].join(' · '),
      // Null, not zero, for a torrent that has not started. A checking, queued
      // or errored torrent has no meaningful bar, and the old row expressed that
      // by conditionally omitting the widget; the plate expresses it in the
      // value, so the same fact is stated once instead of twice.
      progress: _drawsBar(state) ? torrent.progress : null,
      percentage: wholePercent(torrent.progress * 100),
      accent: ServiceKey.qbittorrent.accent,
      statusLabel: state.label,
      statusTone: _toneFor(state),
      metrics: [
        if (torrent.dlSpeed > 0)
          DownloadQueueMetric(
            label: '↓ ${torrent.dlSpeedFormatted}',
            accented: true,
            // The arrow is the whole meaning of this figure and screen readers
            // do not agree on what to do with it: some skip it, some say
            // "downwards arrow". Spelt out, it is a sentence.
            spoken: 'downloading at ${torrent.dlSpeedFormatted}',
          ),
        if (torrent.upSpeed > 0)
          DownloadQueueMetric(
            label: '↑ ${torrent.upSpeedFormatted}',
            spoken: 'uploading at ${torrent.upSpeedFormatted}',
          ),
      ],
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      actions: actions,
    );
  }

  /// Whether this state has a transfer to draw a bar for.
  ///
  /// A complete torrent has no bar either: it is seeding, and a full bar under
  /// a seeding row says "finishing" about something that finished.
  bool _drawsBar(TorrentState state) =>
      torrent.progress < 1 &&
      state != TorrentState.queuedDl &&
      state != TorrentState.queuedUp &&
      state != TorrentState.error;
}

/// qBittorrent's states, in the app's five tones.
///
/// The private tile painted these from the palette directly: accent for
/// downloading, `AppColors.success` for seeding, `AppColors.warning` for
/// stalled, which is both a contrast bug and a vocabulary one. Going through
/// [StatusTone] means the tone rule decides, in the five arms it has everywhere
/// else:
///
///  * **green** for seeding, the only state that means "this one is done";
///  * **amber** for stalled and error, both *faults*: something that should be
///    moving and is not. Red would claim the client did not answer, and it did:
///    it answered by telling us the torrent is stuck;
///  * **blue** for a live download, which is work in flight, for files on
///    their way to another folder, and for a torrent queued for its turn: it
///    is in line, as a queued grab is in an arr's queue, a queued job in
///    SABnzbd's and NZBGet's. It used to be neutral here and in Transmission
///    alone, so one word read in two tones;
///  * **neutral** for paused and unknown: deliberate stops, which are the
///    normal resting state of a torrent client and must not compete for
///    attention with the two states that are actually wrong.
///
/// `error` losing its red is the one that will look like a regression and is
/// not: a torrent qB reports as errored is a fault it reported, and red in this
/// app is reserved for a connection that never replied at all.
StatusTone _toneFor(TorrentState state) => switch (state) {
  TorrentState.seeding => StatusTone.success,
  TorrentState.stalled || TorrentState.error => StatusTone.warning,
  TorrentState.downloading ||
  TorrentState.metaDownloading ||
  TorrentState.checking ||
  TorrentState.movingFiles ||
  TorrentState.queuedDl ||
  TorrentState.queuedUp => StatusTone.info,
  TorrentState.paused || TorrentState.unknown => StatusTone.neutral,
};

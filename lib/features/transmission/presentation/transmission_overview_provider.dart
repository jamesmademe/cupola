/// What the Transmission Overview reads, and the pure functions that shape it.
///
/// Transmission's Overview is cheaper than the \*arr ones and the reason is the
/// API: `torrent-get` already answers **every** row this page draws. Labels,
/// what finished today, what is transferring and the fault on a stalled
/// torrent are all projections of the one list `transmissionTorrentsProvider`
/// holds, so the whole page costs the two calls the service dashboard was
/// making anyway — `session-stats` for the rail and `torrent-get` for the list
/// — plus `session-get` for the daemon's own settings.
///
/// The one genuinely extra call is `free-space`, and it is extra because
/// Transmission will not volunteer it: the path has to come out of
/// `session-get` first, so it cannot be folded into either existing fetch.
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so "finished today" and "how old is this" can be tested at their
/// boundaries without a clock or a container.
///
/// ## What the board asks for that is not here
///
/// The designed Session region draws a peer-port test, a blocklist size with an
/// Update control, and the seed-ratio/idle/encryption triple. None of the three
/// is reachable: `TransmissionSession` keeps eight of the sixty keys
/// `session-get` returns — no `peer-port`, `blocklist-size`, `seedRatioLimit`,
/// `idle-seeding-limit` or `encryption` — and `TransmissionClient` calls
/// neither `port-test` nor `blocklist-update`. So the region draws the four
/// facts the daemon *did* report and says nothing about the three it did not,
/// rather than printing a zero-rule blocklist or a port state nobody tested.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/domain/transmission_tone.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// Rows the Transferring region draws before the Queue tab is the only place
/// the rest are reported. Five, which is what the board draws.
const int transmissionTransferringLimit = 5;

/// Labels the Labels region draws. The header still counts them all.
const int transmissionLabelsPreviewLimit = 6;

/// Rows the Finished today region draws.
const int transmissionFinishedTodayLimit = 3;

// ─── Transferring ───────────────────────────────────────────────────────────

/// Where a torrent sorts in the Transferring region.
///
/// Lower is earlier, and the order is a judgement about attention rather than
/// about throughput: something the daemon has stopped making progress on comes
/// before something that is working, because only the first needs a person.
/// Within a rank the daemon's own [TransmissionTorrent.queuePosition] decides,
/// which is the order the user arranged in Transmission itself — inventing a
/// second ordering on top of theirs is how a queue stops being a queue.
///
/// Returned as an int rather than an enum because it exists only to be sorted
/// on; nothing downstream asks a row which band it landed in.
int transmissionFocusRank(TransmissionTorrent torrent) {
  // A blocking error or a stall. `warning` is the daemon's own test for both,
  // and it deliberately excludes a tracker *warning* — an announce hiccup on an
  // otherwise healthy torrent is not a fault.
  if (torrent.warning != null) return 0;
  // Bytes are meant to be coming in: downloading, checking, or queued for
  // either.
  if (torrent.status.isIncoming) return 1;
  // Seeding and actually pushing bytes.
  if (torrent.rateUpload > 0) return 2;
  // Everything at rest: idle seeds, stopped torrents, things queued to seed.
  return 3;
}

/// The torrents the Overview shows, in the order it shows them.
///
/// Sorted rather than filtered, and that is the whole design of the region: a
/// daemon with nothing downloading still has something worth showing, and a
/// "Transferring" list that filtered to `isIncoming` would be empty on a
/// seedbox that is doing exactly what it was asked to. The header's subtitle
/// carries the honest counts, so the list is free to be a sample of the whole
/// queue rather than a claim about it.
List<TransmissionTorrent> transmissionTransferring(
  List<TransmissionTorrent> torrents, {
  int limit = transmissionTransferringLimit,
}) {
  final sorted = [...torrents];
  sorted.sort((a, b) {
    final byRank = transmissionFocusRank(a).compareTo(transmissionFocusRank(b));
    if (byRank != 0) return byRank;
    final byQueue = a.queuePosition.compareTo(b.queuePosition);
    // Name last, so two torrents the daemon gave the same queue position do not
    // swap places between two polls and make the region flicker.
    return byQueue != 0 ? byQueue : a.name.compareTo(b.name);
  });
  return List.unmodifiable(sorted.take(limit));
}

/// The Transferring header's second line: `2 downloading · 18 seeding`.
///
/// Takes a nullable list and answers `—` for null, because that is the shape
/// the header is in while `torrent-get` is in flight or after it failed.
/// Printing `0 downloading · 0 seeding` over an unanswered question states two
/// facts nobody established.
String transmissionTransferringSubtitle(List<TransmissionTorrent>? torrents) {
  if (torrents == null) return '—';
  final downloading = torrents
      .where((t) => t.status == TransmissionStatus.download)
      .length;
  final seeding = torrents
      .where((t) => t.status == TransmissionStatus.seed)
      .length;
  // Never collapsed to "nothing is transferring": the two counts are different
  // questions and a user with 18 seeds and no downloads is not idle.
  return '$downloading downloading · $seeding seeding';
}

/// The sample of the queue the Overview draws.
final transmissionTransferringProvider =
    FutureProvider.autoDispose<List<TransmissionTorrent>>((ref) async {
      final torrents = await ref.watch(transmissionTorrentsProvider.future);
      return transmissionTransferring(torrents);
    });

// ─── Labels ─────────────────────────────────────────────────────────────────

/// One label and how many torrents wear it.
@immutable
class TransmissionLabelTally {
  const TransmissionLabelTally({required this.label, required this.count});

  final String label;
  final int count;

  /// The row as a sentence. The visible row is a word and a bare numeral, which
  /// read aloud in sequence is "movies ten" — a phrase, not a fact.
  String get spoken =>
      joinSpokenParts([label, count == 1 ? '1 torrent' : '$count torrents']);

  @override
  bool operator ==(Object other) =>
      other is TransmissionLabelTally &&
      other.label == label &&
      other.count == count;

  @override
  int get hashCode => Object.hash(label, count);
}

/// Every label in use, busiest first.
///
/// Derived entirely from the torrent list, because that is the only place
/// Transmission puts them: there is no label registry in this API, a label
/// exists exactly as long as a torrent carries it, and `torrent-get` already
/// asks for the field. A label whose last torrent was removed is therefore
/// gone, which is the daemon's own model and not a rounding error here.
///
/// Whitespace-only labels are dropped rather than tallied under `''`:
/// Transmission accepts them, and a row with no word in it cannot be read
/// aloud or tapped with any meaning.
///
/// Ties break alphabetically so the order is stable between two polls — a
/// `Map`'s insertion order would otherwise reshuffle the region whenever the
/// queue did.
List<TransmissionLabelTally> transmissionLabelTallies(
  List<TransmissionTorrent> torrents,
) {
  final counts = <String, int>{};
  for (final torrent in torrents) {
    for (final raw in torrent.labels) {
      final label = raw.trim();
      if (label.isEmpty) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
  }

  final tallies = counts.entries
      .map((e) => TransmissionLabelTally(label: e.key, count: e.value))
      .toList();
  tallies.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.label.compareTo(b.label);
  });
  return List.unmodifiable(tallies);
}

/// Every label in use. The screen caps the rows it draws; the header counts the
/// whole list, so a seventh label is reported even when it is not drawn.
final transmissionLabelsProvider =
    FutureProvider.autoDispose<List<TransmissionLabelTally>>((ref) async {
      final torrents = await ref.watch(transmissionTorrentsProvider.future);
      return transmissionLabelTallies(torrents);
    });

// ─── Session ────────────────────────────────────────────────────────────────

/// One line of the Session region: what the setting is, what it is set to, and
/// why that matters.
@immutable
class TransmissionSessionFact {
  const TransmissionSessionFact({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.tone = StatusTone.neutral,
  });

  /// The setting's name — `Slow mode`, `Download limit`.
  final String label;

  /// Its value, already rendered. `—` when the daemon did not answer.
  final String value;

  /// Why the value is worth a line. Empty when it is self-evident.
  final String detail;

  final IconData icon;

  /// How the value reads. Neutral for every setting at rest — **none of these
  /// is ever a fault**, which is the trap this region walks past: a throttle
  /// the user switched on themselves painted amber turns a deliberate choice
  /// into an alarm.
  final StatusTone tone;

  /// The row's first line — `Download limit · Not limited`.
  ///
  /// Label and value together, and **not** in the row's trailing slot, which is
  /// capped at 132pt with `maxLines: 1` because it was shaped for Prowlarr's
  /// digit figures. Every value in this region is prose — `Not limited`,
  /// `Stopped (0 KB/s)` — and at an accessibility reading size that cap holds
  /// about seven characters, so the row's entire content would ellipsise away
  /// and leave `Download limit …` saying nothing. The board agrees: its Session
  /// rows read `Peer port 51413` and `Blocklist · 342 k rules` on the title
  /// line, with the qualifier under them and no right-hand figure at all.
  String get titleLine => '$label · $value';

  String get spoken =>
      joinSpokenParts([label, value, spokenFromDotted(detail)]);
}

/// A Transmission speed limit, rendered.
///
/// Kilobytes per second, which is the API's unit for every *limit* it accepts
/// even though every *rate* it reports is bytes per second. The unit is printed
/// rather than converted: a user comparing this against Transmission's own
/// preferences window should see the same number they typed there.
///
/// A limit that is switched off reads `Not limited` rather than its stored
/// value — Transmission keeps the number while the flag is false, so printing
/// it would claim a ceiling that is not in force.
String transmissionLimitLabel(int kbPerSec, {required bool enabled}) {
  if (!enabled) return 'Not limited';
  // A limit of zero *is* enforced by Transmission and means "stop": worth
  // saying in words, because "0 KB/s" beside a running download reads as a
  // rendering bug rather than as the cause.
  if (kbPerSec <= 0) return 'Stopped (0 KB/s)';
  return '$kbPerSec KB/s';
}

/// The Session region's rows, from what `session-get` and `free-space`
/// answered.
///
/// [freeSpaceBytes] is null when the free-space call was never made or came
/// back unusable; it renders `—` and not `0 B`, because "the disk is full" and
/// "nobody asked" are opposite readings of the same glyph.
List<TransmissionSessionFact> transmissionSessionFacts(
  TransmissionSession session, {
  int? freeSpaceBytes,
}) {
  final downloadDir = session.downloadDir.trim();

  return List.unmodifiable([
    TransmissionSessionFact(
      label: 'Slow mode',
      value: session.altSpeedEnabled ? 'On' : 'Off',
      // The whole reason this row leads the region: it is the answer to "why is
      // it slow", and without it the rail's rates look like a fault.
      detail: session.altSpeedEnabled
          ? 'alternative limits are in force'
          : 'the global limits apply',
      icon: session.altSpeedEnabled
          ? Icons.hourglass_bottom_rounded
          : Icons.speed_rounded,
      // Informational, never a fault: the user switched this on. Blue is the
      // arm for a state that explains what you are seeing; amber is reserved
      // for something that went wrong on its own.
      tone: session.altSpeedEnabled ? StatusTone.info : StatusTone.neutral,
    ),
    TransmissionSessionFact(
      label: 'Download limit',
      value: transmissionLimitLabel(
        session.speedLimitDownKbPerSec,
        enabled: session.speedLimitDownEnabled,
      ),
      detail: '',
      icon: Icons.south_rounded,
    ),
    TransmissionSessionFact(
      label: 'Upload limit',
      value: transmissionLimitLabel(
        session.speedLimitUpKbPerSec,
        enabled: session.speedLimitUpEnabled,
      ),
      detail: '',
      icon: Icons.north_rounded,
    ),
    TransmissionSessionFact(
      label: 'Free space',
      // `formatSize` answers `—` for anything at or below zero, which is the
      // right reading of both cases it covers here: a daemon that did not
      // report a figure, and one that reported a nonsensical one.
      value: freeSpaceBytes == null ? '—' : formatSize(freeSpaceBytes),
      // The path is the point. Every path in this API belongs to the *daemon's*
      // filesystem, so `/downloads` in a container is not the user's
      // `/downloads`, and a free-space figure with no path attached is a number
      // about an unnamed disk.
      detail: downloadDir.isEmpty ? 'download directory unknown' : downloadDir,
      icon: Icons.sd_storage_outlined,
    ),
  ]);
}

/// Free bytes at the daemon's default download directory, or null.
///
/// Two calls, in order, because Transmission will not answer the second without
/// the first: `free-space` takes a path and the only path the app knows is the
/// one `session-get` reports.
///
/// **Null rather than a throw.** A daemon that answers `session-get` and
/// refuses `free-space` — an unreadable path, a relocated volume, an older
/// build — has still told us everything else in the region, and taking three
/// good rows down to report a missing fourth is the trade the em-dash rule
/// exists to refuse.
///
/// Zero is folded into null for the same reason: `TransmissionClient.freeSpace`
/// collapses a missing `size-bytes` key to `0`, so at this layer a zero cannot
/// be told from silence and must not be printed as a measurement.
final transmissionFreeSpaceProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  final session = await ref.watch(transmissionSessionProvider.future);
  final path = session.downloadDir.trim();
  if (path.isEmpty) return null;
  try {
    final bytes = await ref.watch(transmissionClientProvider).freeSpace(path);
    return bytes > 0 ? bytes : null;
  } catch (_) {
    return null;
  }
});

/// The Session region.
///
/// Derived from [transmissionSessionProvider], which carries no `retry:`
/// override — so neither does this, and the derivation propagates the source's
/// behaviour rather than quietly changing it. The screen gates on
/// `isServiceConfigured` before any of this is watched, so the one condition no
/// amount of retrying could fix never reaches a provider at all.
final transmissionSessionFactsProvider =
    FutureProvider.autoDispose<List<TransmissionSessionFact>>((ref) async {
      final session = await ref.watch(transmissionSessionProvider.future);
      final free = await ref.watch(transmissionFreeSpaceProvider.future);
      return transmissionSessionFacts(session, freeSpaceBytes: free);
    });

// ─── Finished today ─────────────────────────────────────────────────────────

/// One torrent that finished downloading today.
@immutable
class TransmissionFinishedItem {
  const TransmissionFinishedItem({
    required this.name,
    required this.detail,
    required this.ratioLabel,
    required this.tone,
    required this.doneAt,
  });

  final String name;

  /// Size, how long ago, and what it is doing now.
  final String detail;

  /// `ratio 2.60`, or `—` when Transmission did not report one.
  final String ratioLabel;

  final StatusTone tone;

  final DateTime doneAt;

  String get spoken =>
      joinSpokenParts([name, spokenFromDotted(detail), ratioLabel]);
}

/// The torrents whose download completed on the local calendar day of [now].
///
/// **Local, and a calendar day rather than a rolling twenty-four hours**, for
/// the reason the region is headed `today`: a heading is a promise, and a
/// torrent that finished at 23:50 last night is not today's news however recent
/// it feels. Transmission reports `doneDate` as epoch **seconds**, and `0` when
/// it never finished — unguarded that renders as 1 January 1970, which is how a
/// "finished today" list fills up with torrents that never did.
///
/// Sorted newest first, capped at [limit].
List<TransmissionFinishedItem> transmissionFinishedToday(
  List<TransmissionTorrent> torrents, {
  required DateTime now,
  int limit = transmissionFinishedTodayLimit,
}) {
  final local = now.toLocal();
  final items = <TransmissionFinishedItem>[];

  for (final torrent in torrents) {
    if (torrent.doneDate <= 0) continue;
    final doneAt = DateTime.fromMillisecondsSinceEpoch(
      torrent.doneDate * 1000,
    ).toLocal();
    if (doneAt.year != local.year ||
        doneAt.month != local.month ||
        doneAt.day != local.day) {
      continue;
    }

    items.add(
      TransmissionFinishedItem(
        name: torrent.name,
        detail: joinDisplayParts([
          // The size on disk, not what is left: nothing is left.
          formatSize(torrent.totalSize),
          // The app's one vocabulary for an age — `just now`, `14 min ago`,
          // `2 h ago` — so this row compares with every other aged figure in
          // the app instead of inventing a fourth phrasing.
          formatSampleAge(doneAt, now: now),
          // The daemon's own sentence when it has one, its plain status
          // otherwise.
          (torrent.warning ?? torrent.status.label).toLowerCase(),
        ]),
        // `-1` is Transmission's "no ratio" sentinel and `ratioLabel` already
        // renders it as an em dash.
        ratioLabel: torrent.uploadRatio < 0
            ? '—'
            : 'ratio ${torrent.ratioLabel}',
        // The app's one reading of Transmission's eight states, shared with the
        // queue plate two regions above. It used to be a second switch here
        // that guarded `warning` and `stopped` and fell through to green for
        // everything else — so a torrent queued to seed, one being re-verified
        // and one whose status code this app has no name for all drew a green
        // dot beside a detail line saying otherwise, while the same torrent
        // was a neutral chip in Transferring. Green is never a fallthrough.
        tone: transmissionTorrentTone(torrent),
        doneAt: doneAt,
      ),
    );
  }

  items.sort((a, b) => b.doneAt.compareTo(a.doneAt));
  return List.unmodifiable(items.take(limit));
}

/// What finished today.
final transmissionFinishedTodayProvider =
    FutureProvider.autoDispose<List<TransmissionFinishedItem>>((ref) async {
      final torrents = await ref.watch(transmissionTorrentsProvider.future);
      return transmissionFinishedToday(torrents, now: DateTime.now());
    });

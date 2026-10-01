/// What the Unraid Overview reads, and the pure functions that shape it.
///
/// Everything on this page is folded from the **three documents
/// [UnraidClient] speaks** — `info`, `array` and `dockerContainers` — and two
/// of them are already loaded by the service home: the KPI rail reads
/// [unraidArrayProvider] and [unraidDockerProvider]. Only `info` is a call this
/// page adds, and it is the one that carries the uptime and the release the
/// board prints on the identity line.
///
/// Every windowing and folding rule lives in a top-level pure function taking
/// an explicit `now` where it needs a clock, so the boundaries are testable
/// without a container and without waiting for one.
///
/// ## What is deliberately not here
///
/// The board draws Parity, VMs, Notifications, Shares and a CPU/RAM/Net strip.
/// None of them is stubbed, because `UnraidClient` makes no call that could
/// fill them and the committed SDL (`test/fixtures/unraid/schema.graphql`) —
/// which is this app's contract with the API — declares no field for them
/// either. A section given a fake zero is worse than a section that was never
/// promised: "0 notifications" is a sentence about a quiet server, and what we
/// actually have is silence about a question nobody asked.
///
/// Unraid has never been run against a real instance here, which is the second
/// reason nothing below is guessed: every figure this file produces comes from
/// a field the three committed queries name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// Disk rows the Array section draws before its header is the only place the
/// rest are reported.
///
/// Six, which is a whole small array — the header states the census either way,
/// and [unraidDiskPreview] floats anything wrong to the top so a preview can
/// never be the reason a failing slot went unseen.
const int unraidDiskPreviewLimit = 6;

/// Container rows the Docker section draws.
const int unraidContainerPreviewLimit = 5;

// ─── System (`info`) ────────────────────────────────────────────────────────

/// System information, straight from `query { info { os { … } } }`.
///
/// Its own provider rather than a field of the two the KPI rail already loads:
/// `info` is a separate document, this is the only page that draws it, and a
/// page that folded it into the array call would make the Array tab pay for a
/// fetch it never reads.
///
/// `retry: noProviderRetry`, because [unraidClientProvider] throws
/// `Unraid not configured` — a condition no amount of waiting changes, so a
/// backoff here is a timer that never stops and a battery cost that never buys
/// anything. The screen checks `isServiceConfigured` before this is ever
/// watched; this is the belt to that braces.
final unraidInfoProvider = FutureProvider.autoDispose<UnraidInfo>((ref) async {
  return ref.watch(unraidClientProvider).getInfo();
}, retry: noProviderRetry);

/// One line of the System section: a figure and the word for it.
@immutable
class UnraidSystemFact {
  const UnraidSystemFact({
    required this.label,
    required this.value,
    required this.icon,
  });

  /// `Uptime`, `Release`.
  final String label;

  /// The figure, or `—` when Unraid answered without it.
  final String value;

  final IconData icon;

  /// Label first, figure second — the order a person says it, which is the
  /// inverse of the visual order the row draws (figure large, label under it).
  String get spoken => joinSpokenParts([label, value]);
}

/// `18 days`, `7 hours`, `12 minutes` — how long the server has been up.
///
/// `info.os.uptime` is typed `String` in the SDL and carries a **boot
/// timestamp**, not a duration (`2026-07-01T00:00:00Z` in the committed
/// fixture), so the elapsed time has to be computed against [now] rather than
/// printed. That is the whole reason this is a pure function taking an explicit
/// clock: every boundary below is a test, and none of them needs to wait.
///
/// Null — which the row renders as `—` — in three cases, and each is a figure
/// we do not have rather than a zero we could print:
///
///  * the field was absent or blank;
///  * it was not a timestamp. Some releases may answer a pre-rendered string;
///    re-basing a value whose shape we cannot read would be a guess, and this
///    file guesses nothing about an API nobody here has run;
///  * the boot time is in the future. That is clock skew between the phone and
///    the server, and "up minus three hours" is not a fact about anything.
String? unraidUptimeLabel(String? raw, {required DateTime now}) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;

  final boot = DateTime.tryParse(value);
  if (boot == null) return null;

  // Compared in UTC on both sides: the server answers with an offset and the
  // phone's `now` is local, and a difference taken across two zones is wrong by
  // exactly the offset between them.
  final elapsed = now.toUtc().difference(boot.toUtc());
  if (elapsed.isNegative) return null;

  if (elapsed.inDays >= 1) return _plural(elapsed.inDays, 'day');
  if (elapsed.inHours >= 1) return _plural(elapsed.inHours, 'hour');
  if (elapsed.inMinutes >= 1) return _plural(elapsed.inMinutes, 'minute');
  // A server up for forty seconds has just come back, and that is the useful
  // reading — not `0 minutes`, which looks like a figure that failed to load.
  return 'just booted';
}

/// The two facts `info` can answer, in reading order.
///
/// Both carry `—` rather than being dropped when Unraid answered without them:
/// the section exists because the server replied, and a row that vanishes on a
/// missing field makes the page's shape depend on the payload.
List<UnraidSystemFact> unraidSystemFacts(
  UnraidInfo info, {
  required DateTime now,
}) {
  final uptime = unraidUptimeLabel(info.uptime, now: now);
  final release = joinDisplayParts([
    info.distro.trim(),
    info.version.trim(),
  ], separator: ' ');

  return List.unmodifiable([
    UnraidSystemFact(
      label: 'Uptime',
      value: uptime ?? '—',
      icon: Icons.schedule_rounded,
    ),
    UnraidSystemFact(
      label: 'Release',
      value: release.isEmpty ? '—' : release,
      icon: Icons.memory_rounded,
    ),
  ]);
}

/// The System section's two rows.
///
/// Carries `noProviderRetry` because [unraidInfoProvider] does: a derivation
/// that drops it reintroduces, one step down, exactly the backoff its source
/// refused.
final unraidOverviewSystemProvider =
    FutureProvider.autoDispose<List<UnraidSystemFact>>((ref) async {
      final info = await ref.watch(unraidInfoProvider.future);
      return unraidSystemFacts(info, now: DateTime.now());
    }, retry: noProviderRetry);

// ─── Array ──────────────────────────────────────────────────────────────────

/// `5.6 of 9.3 TB`, or null when the array answered with no capacity block.
///
/// Null and never `0 B`: the percentage beside it on the readout rail is the
/// figure a user acts on, and an array that reports no capacity is one we
/// cannot say anything about — including that it is empty.
///
/// One decimal, from the shared ladder in `byte_format.dart`: a 31.2 TB array
/// and a 31.9 TB one read apart, and this is a figure the user watches grow.
///
/// The unit is printed once when both figures land on the same one, because
/// that is how the board draws it and how a person reads it aloud. When they
/// differ — 800 GB used of 9.3 TB — both units stay, since collapsing them
/// there would be off by a factor of a thousand.
String? unraidCapacityLabel(UnraidArray array) {
  final used = array.usedBytes;
  final total = array.totalBytes;
  if (used == null || total == null || total <= 0) return null;

  final usedLabel = formatBytes(used);
  final totalLabel = formatBytes(total);
  final usedUnit = usedLabel.split(' ').last;
  final totalUnit = totalLabel.split(' ').last;
  if (usedUnit == totalUnit) {
    return '${usedLabel.substring(0, usedLabel.length - usedUnit.length - 1)} '
        'of $totalLabel';
  }
  return '$usedLabel of $totalLabel';
}

/// The word the header prints for the array's state, or null when it has none.
///
/// Lower-cased because it sits in a sentence of facts, not in a badge — the
/// readout rail above prints the API's own `STARTED` in its cell. `UNKNOWN` is
/// the model's stand-in for an absent field rather than a state the array
/// reported, so it is dropped: an array that did not say is not an array in an
/// unknown state.
String? unraidArrayStateLabel(String state) {
  final value = state.trim();
  if (value.isEmpty || value.toUpperCase() == 'UNKNOWN') return null;
  return value.toLowerCase();
}

/// Everything the Array section needs, folded once.
@immutable
class UnraidArrayDigest {
  const UnraidArrayDigest({
    required this.stateLabel,
    required this.capacityLabel,
    required this.diskCount,
    required this.warmCount,
    required this.faultCount,
    required this.preview,
  });

  /// `started`, or null when the array reported no state.
  final String? stateLabel;

  /// `5.6 of 9.3 TB`, or null when it reported no capacity.
  final String? capacityLabel;

  /// Every slot the array answered with — **not** the length of [preview], and
  /// **null** when the array answered with no slot list at all.
  ///
  /// `array.disks` is the whole list: the query is not paged and nothing caps
  /// it, so a list the server sent is a census and may honestly be stated as a
  /// total. The preview below is a sample of it and its length may never be.
  ///
  /// A list the server did *not* send is neither. `disks` is nullable in the
  /// committed SDL and this app has never run against a real instance, so the
  /// absent case is real; printing `0 disks` for it asserts an array with no
  /// drives out of silence, which is the reading a user acts on.
  final int? diskCount;

  /// Slots at or above [UnraidDisk.warmThresholdCelsius] that are **not**
  /// already flagged.
  ///
  /// The subtraction runs this way round on purpose. A drive can be both — a
  /// `DISK_DSBL` slot at 47 °C is the array running without a drive it expected
  /// while that drive cooks — and one of the two clauses has to give it up so
  /// the headline does not report one drive as two problems. The clause that
  /// gives it up is this one, because the other names the more serious fact.
  final int warmCount;

  /// Slots the array has flagged — a disabled or invalid slot, which is the
  /// array telling us it is running without a drive it expected.
  ///
  /// Counted whatever the temperature says: a flagged slot is never dropped
  /// from this count, only from [warmCount].
  final int faultCount;

  final List<UnraidDisk> preview;

  /// `started · 5.6 of 9.3 TB · 8 disks · 1 above 45 °C`.
  ///
  /// The used **percentage** is deliberately absent: the readout rail directly
  /// above this section already carries it, and a header repeating the cell an
  /// inch above it is noise. What the rail cannot carry is the pair of absolute
  /// figures, which is why they are here.
  ///
  /// The two fault clauses appear only when they are non-zero. A header reading
  /// `0 above 45 °C` is a sentence about a problem where there is none, and on
  /// a page whose job is to say what needs a decision that is the most
  /// expensive kind of noise.
  String get headline => joinDisplayParts([
    stateLabel,
    capacityLabel,
    if (diskCount != null) diskCount == 1 ? '1 disk' : '$diskCount disks',
    if (warmCount > 0) '$warmCount above ${UnraidDisk.warmThresholdCelsius} °C',
    if (faultCount > 0) '$faultCount slot${faultCount == 1 ? '' : 's'} flagged',
  ]);
}

/// Faulted and warm slots first, then the array's own order, capped at [limit].
///
/// Stable within each group, so the second half still reads in slot order —
/// parity, disk1, disk2 — which is how the user's own Unraid web UI lists them.
///
/// The float is not cosmetic. A preview of six over an array of thirty would
/// otherwise hide the one disk that is failing behind five that are fine, and a
/// fault a preview can hide is a fault the page failed to report.
List<UnraidDisk> unraidDiskPreview(
  List<UnraidDisk> disks, {
  int limit = unraidDiskPreviewLimit,
}) {
  final flagged = disks.where((disk) => disk.tone == StatusTone.warning);
  final rest = disks.where((disk) => disk.tone != StatusTone.warning);
  return List.unmodifiable([...flagged, ...rest].take(limit));
}

/// The array, folded into what the section draws.
UnraidArrayDigest unraidArrayDigest(
  UnraidArray array, {
  int limit = unraidDiskPreviewLimit,
}) {
  return UnraidArrayDigest(
    stateLabel: unraidArrayStateLabel(array.state),
    capacityLabel: unraidCapacityLabel(array),
    // Only a list the array actually sent is a census. Silence is not zero.
    diskCount: array.reportedDisks ? array.disks.length : null,
    // Warm is a temperature, flagged is a slot status, and a disk can be both.
    // Each drive is attributed once, to the more serious of its two troubles:
    // every flagged slot is counted as flagged, and only an unflagged drive
    // over the threshold is counted as warm. Nothing in the headline is
    // double-reported, and nothing is dropped.
    warmCount: array.disks.where((disk) => disk.warm && !disk.flagged).length,
    faultCount: array.disks.where((disk) => disk.flagged).length,
    preview: unraidDiskPreview(array.disks, limit: limit),
  );
}

/// The Array section's fold.
///
/// Carries `noProviderRetry` because [unraidArrayProvider] carries it: a
/// derivation that dropped it would reintroduce, one step down, exactly the
/// backoff its source refused. The claim is only worth writing because the
/// source now makes it — this override sat here while `unraidArrayProvider` was
/// still on Riverpod's default, where it bought nothing: a fold cannot settle
/// before the thing it awaits.
final unraidOverviewArrayProvider =
    FutureProvider.autoDispose<UnraidArrayDigest>((ref) async {
      return unraidArrayDigest(await ref.watch(unraidArrayProvider.future));
    }, retry: noProviderRetry);

/// `38 °C`, or `spun down` for a slot Unraid is reading no temperature from.
///
/// The Array tab already states this rule and this must not contradict it: a
/// drive with no reading is asleep, not at zero. The unit is spaced as the
/// board spells it (`47 °C`), and the word replaces the figure entirely rather
/// than standing beside an em dash — we know exactly why the figure is missing,
/// and saying so is better than saying nothing.
String unraidDiskReading(UnraidDisk disk) =>
    disk.spunDown ? 'spun down' : '${disk.temp} °C';

/// The disk row as one sentence.
///
/// `degrees`, not `°C`: a screen reader reads the degree sign as "degree sign"
/// or drops it, and neither is what the row means. Same phrasing the Array tab
/// speaks, because two tabs of one service describing the same drive in two
/// different sentences is how a user stops trusting either.
String unraidDiskSpoken(UnraidDisk disk) => joinSpokenParts([
  disk.name,
  if (disk.status.isNotEmpty) disk.status,
  disk.spunDown ? 'spun down' : '${disk.temp} degrees',
]);

// ─── Docker ─────────────────────────────────────────────────────────────────

/// Everything the Docker section needs, folded once.
@immutable
class UnraidDockerDigest {
  const UnraidDockerDigest({
    required this.total,
    required this.running,
    required this.stopped,
    required this.unhealthy,
    required this.failed,
    required this.preview,
  });

  /// Every container `dockerContainers` answered with. The query is not paged,
  /// so this is a census and may be stated as a total — unlike the length of
  /// [preview], which never may.
  final int total;

  final int running;

  /// Exited cleanly, i.e. somebody stopped it. **Backlog, not a fault**, and
  /// counted in the plain ink for exactly that reason.
  final int stopped;

  final int unhealthy;

  /// Exited with a non-zero code, stuck in a restart loop, or dead.
  final int failed;

  final List<UnraidDockerContainer> preview;

  /// `14 containers · 13 running · 1 stopped · 1 unhealthy`.
  ///
  /// Same arms and the same words as the Docker tab's own tally, so the two
  /// tabs agree; only the non-zero ones are printed, because "0 unhealthy" is a
  /// sentence about a problem that does not exist.
  String get headline => joinDisplayParts([
    total == 1 ? '1 container' : '$total containers',
    if (running > 0) '$running running',
    if (stopped > 0) '$stopped stopped',
    if (unhealthy > 0) '$unhealthy unhealthy',
    if (failed > 0) '$failed failed',
  ]);
}

/// Faults first, then alphabetical, capped at [limit].
///
/// Faults first for the reason [unraidDiskPreview] floats a failing slot: five
/// rows out of forty containers would otherwise report the alphabet rather than
/// the problem. Alphabetical after that, which is the order the Docker tab
/// lists them in.
///
/// A **stopped** container is not floated. It is backlog — the user stopped it,
/// they know — and promoting it would make the top of the section a list of
/// decisions already taken.
List<UnraidDockerContainer> unraidContainerPreview(
  List<UnraidDockerContainer> containers, {
  int limit = unraidContainerPreviewLimit,
}) {
  int byName(UnraidDockerContainer a, UnraidDockerContainer b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  final faulted = [...containers.where((c) => c.tone == StatusTone.warning)]
    ..sort(byName);
  final rest = [...containers.where((c) => c.tone != StatusTone.warning)]
    ..sort(byName);
  return List.unmodifiable([...faulted, ...rest].take(limit));
}

/// The container list, folded into what the section draws.
UnraidDockerDigest unraidDockerDigest(
  List<UnraidDockerContainer> containers, {
  int limit = unraidContainerPreviewLimit,
}) {
  int count(UnraidContainerCondition condition) =>
      containers.where((c) => c.condition == condition).length;

  return UnraidDockerDigest(
    total: containers.length,
    running: count(UnraidContainerCondition.running),
    stopped: count(UnraidContainerCondition.stopped),
    unhealthy: count(UnraidContainerCondition.unhealthy),
    failed:
        count(UnraidContainerCondition.exitedUnexpectedly) +
        count(UnraidContainerCondition.restarting) +
        count(UnraidContainerCondition.dead),
    preview: unraidContainerPreview(containers, limit: limit),
  );
}

/// The Docker section's fold, carrying `noProviderRetry` because
/// [unraidDockerProvider] carries it — see [unraidOverviewArrayProvider].
final unraidOverviewDockerProvider =
    FutureProvider.autoDispose<UnraidDockerDigest>((ref) async {
      return unraidDockerDigest(await ref.watch(unraidDockerProvider.future));
    }, retry: noProviderRetry);

// ─── Shared ─────────────────────────────────────────────────────────────────

/// `1 day`, `18 days`. English-only, like the weekday names in the Radarr
/// Overview and for the same reason: there is no `intl` dependency to reach
/// for, and English-only is a decision here rather than debt.
String _plural(int count, String unit) =>
    '$count $unit${count == 1 ? '' : 's'}';

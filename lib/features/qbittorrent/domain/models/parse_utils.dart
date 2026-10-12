import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/unit_space.dart';

int parseInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double parseDouble(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

/// Lenient bool parser for qBittorrent API responses, which historically mix
/// `true`/`false`, `1`/`0`, and their string equivalents across versions and
/// endpoints (notably `is_private`, `force_start`, `super_seeding`).
///
/// - `null` → `false`
/// - `bool` passes through
/// - `num`: any non-zero value is `true`; `0` is `false`
/// - Everything else: case-insensitive match on `'true'` or `'1'`
bool parseBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1';
}

/// Size rendering for qBittorrent, and, through this file, for Transmission,
/// NPM and the TrueNAS screens.
///
/// The ladder itself is [formatBytes]; all this adds is qB's sentinel.
/// `<= 0` means "not known yet" across these APIs (a magnet with no metadata
/// reports size 0, several fields report -1), so it renders as `—` rather than
/// claiming the thing is empty.
String formatSize(int bytes) => bytes <= 0 ? '—' : formatBytes(bytes);

/// Rate rendering for qBittorrent, Transmission and the /services KPI grid.
///
/// The ladder is [formatBytesPerSecond]; all this adds is qB's idle sentinel,
/// `0 B/s` for anything `<= 0` (qB reports 0 when idle and -1 for "no limit"
/// on the fields that share this formatter).
///
/// There is one ladder on purpose: these rates land in the same KPI grid as
/// SABnzbd's and NZBGet's, and two services' download speeds rendering to
/// different precision in adjacent cells is the exact defect the shared
/// formatter exists to prevent.
String formatSpeed(int bytesPerSecond) => bytesPerSecond <= 0
    ? withUnit(0, 'B/s')
    : formatBytesPerSecond(bytesPerSecond);

/// Human-readable duration.
///
/// Returns `''` for `seconds <= 0` so callers can decide what "empty" means
/// (e.g. `—` for never-seen, or just an empty cell for freshly added). For
/// positive inputs renders as `'X d HH:MM:SS'` (omitting the day prefix when
/// `d == 0`), the clock form of the qBittorrent WebUI's General tab with the
/// day count in the brand book's unit (`3 d 04:05:06`).
String formatDuration(int seconds) {
  if (seconds <= 0) return '';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final hh = h.toString().padLeft(2, '0');
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (d > 0) return '${withUnit(d, 'd')} $hh:$mm:$ss';
  return '$hh:$mm:$ss';
}

/// qBittorrent per-torrent speed-limit rendering.
///
/// - `< 0` (qB's unlimited sentinel) → `'∞'`
/// - `== 0` (qB's "limit cleared" state) → `'0'` (NOT `'0 B/s'`, to match
///   the WebUI's discrete "0 / ∞" pair)
/// - positive → `formatSpeed`
String formatLimit(int bytesPerSecond) {
  if (bytesPerSecond < 0) return '∞';
  if (bytesPerSecond == 0) return '0';
  return formatSpeed(bytesPerSecond);
}

/// Local-time `YYYY-MM-DD HH:MM` rendering of a Unix epoch in seconds.
///
/// Returns `'—'` for `seconds <= 0` (covers both 0 = "never" and qB's -1
/// sentinels). The stamp itself is the app's one, [formatDateTimeStamp].
String formatEpochDate(int seconds) {
  if (seconds <= 0) return '—';
  return formatDateTimeStamp(
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
  );
}

/// Same rendering as [formatDuration] but reserved for "relative time"
/// call-sites (e.g. "Reannounce in" countdowns). Identical for now; the split
/// keeps the door open for a future locale-aware variant.
String formatRelativeSeconds(int seconds) {
  if (seconds <= 0) return '';
  return formatDuration(seconds);
}

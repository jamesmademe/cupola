/// One place where a byte count becomes a string.
///
/// Five call sites independently grew their own copy of this: SABnzbd's
/// `_formatMb`/`_formatBytes`/`speedLabel`, NZBGet's `formatNzbgetRate`/
/// `formatNzbgetMb`, qBittorrent's `formatSize`/`formatSpeed` (also used by
/// Transmission, NPM and every TrueNAS screen) and Interactive Search's
/// `formatReleaseSize`, with different unit ladders and different precision
/// rules, so the same 1.46 GiB rendered as `1.5 GB` on one dashboard and
/// `1500 MB` on another. Later the shared ladder itself kept two precisions (two
/// significant digits for glances, three for comparisons), and the same file
/// still read `4 GB` in one cell and `4.38 GB` in the next. There is one rule
/// now, and one ladder.
///
/// The rule:
///
///  * **Binary units** (1024-based), labelled `B`/`KB`/`MB`/`GB`/`TB`/`PB`.
///    Every service reports binary quantities under those labels, and the
///    numbers have to agree with the service's own web UI: a 4.4 GB release
///    here is the 4.4 GB Sonarr, qBittorrent and SABnzbd show. Decimal units
///    (1000-based) would be the SI-correct choice and the wrong one for this
///    app, because the user compares against those screens.
///  * **Bytes are whole things.** `B` never carries a decimal; `512 B`, not
///    `512.0 B`.
///  * **One decimal above bytes**, always: `4.0 GB`, `4.4 GB`,
///    `45.5 TB`, `4.2 MB/s`. A size the user compares (two releases, a pool
///    against its free space) keeps the digit that tells them apart, and a size
///    does not change width as it grows from `9.9 GB` to `10.0 GB`.
///  * **Whole from 100 up in a unit**: `152 GB`, `999 KB`, `120 MB/s`. A third
///    significant digit already says the figure to within a percent, and the
///    decimal after it is false precision (and a longer string in a cell that
///    has to hold `999 KB`). The edge is read *after* rounding, so 99.96 GB
///    prints `100 GB`, never `100.0 GB`.
///  * **Promotion happens after rounding**, so 1023.96 KB prints `1.0 MB`
///    rather than the self-contradicting `1024.0 KB` or `1024 KB`.
///  * **A rate follows the same rule** with `/s` appended.
///  * **A no-break space between the figure and the unit** (`4.4 GB`,
///    `4.2 MB/s`, `120 of 152 GB`), `unitSpace`, so a figure never splits from
///    its unit across two lines. Whoever takes a label apart splits on
///    `unitSpace`, not on a plain space.
///
/// A fixed decimal count with no edge is what produced both `1500 MB` and
/// `2048.00 GB` in the copies this replaces; the edge and the promotion are
/// what keep the ladder from doing the same.
///
/// There is deliberately no second, "precise" ladder: two functions that meant
/// the same thing at different widths are how the defect above came back.
/// Unit-specific wrappers ([formatMegabytes], [formatKilobytesPerSecond]) only
/// convert what an API reports into bytes. [formatBytesOfTotal] is the one
/// extra shape, for a progress pair, and takes its digits from the same rule.
library;

import 'package:cupola/core/utils/unit_space.dart';

const List<String> _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

const int _kib = 1024;

/// A magnitude from this value up has no decimal: `152 GB`, not `152.3 GB`.
const double _wholeFrom = 100;

/// Renders a size in bytes: `0 B`, `512 B`, `1.5 GB`, `5.0 TB`, `152 GB`.
String formatBytes(num bytes) => _format(bytes.toDouble(), '');

/// Renders a transfer rate in bytes per second: `512 B/s`, `2.0 MB/s`,
/// `120 MB/s`.
String formatBytesPerSecond(num bytesPerSecond) =>
    _format(bytesPerSecond.toDouble(), '/s');

/// Renders a size reported in whole megabytes: SABnzbd's `mbleft`/`mb` and
/// NZBGet's `*SizeMB` fields, which is how both APIs report queue sizes.
String formatMegabytes(num megabytes) =>
    formatBytes(megabytes.toDouble() * _kib * _kib);

/// Renders a rate reported in kilobytes per second: SABnzbd's `kbpersec`.
String formatKilobytesPerSecond(num kilobytesPerSecond) =>
    formatBytesPerSecond(kilobytesPerSecond.toDouble() * _kib);

/// Renders [done] against [total] with the unit written once, on the **total's**
/// unit: `1.0 of 4.0 GB`, `120 of 152 GB`, `0.4 of 4.0 GB`, `300 of 512 B`.
///
/// Formatted independently, a transfer 900 MB into a 15.2 GB file reads
/// `900 MB of 15.2 GB`, which asks the reader to convert before they can see it
/// is nowhere near done. One unit makes the pair comparable at a glance, which
/// is the only reason both numbers are on the row.
///
/// Each half follows the rule of the library above, so a done figure below one
/// unit reads `0.4`, not `0`, and the whole-number edge applies to each half on
/// its own: `5.2 of 152 GB` and `120 of 152 GB`. Bytes are whole.
///
/// [total] must be positive and [done] not negative; a caller that does not
/// know one of them prints its own placeholder instead of calling this.
String formatBytesOfTotal(num done, num total) {
  final totalText = _ladder(total.toDouble());
  if (totalText.unit == 0) {
    return '${done.round()} of ${withUnit(totalText.text, 'B')}';
  }
  final scale = _pow1024(totalText.unit);
  final doneText = _scaled(done.toDouble() / scale);
  return '$doneText of ${withUnit(totalText.text, _units[totalText.unit])}';
}

String _format(double value, String suffix) {
  final sign = value.isNegative ? '-' : '';
  final magnitude = value.abs();
  if (!magnitude.isFinite) return '—';

  final rung = _ladder(magnitude);
  return '$sign${withUnit(rung.text, '${_units[rung.unit]}$suffix')}';
}

/// The unit [magnitude] lands on, and its text on that unit.
({int unit, String text}) _ladder(double magnitude) {
  var value = magnitude;
  var unit = 0;
  while (true) {
    // Bytes are indivisible; above that the number is whatever the rule
    // prints at this unit.
    final text = unit == 0 ? value.toStringAsFixed(0) : _scaled(value);
    // Rounding can push a value back over the promotion threshold (1023.96 KB
    // renders as "1024"), so the check reads the *rendered* number, not the
    // raw one, otherwise the string contradicts its own unit.
    if (unit == _units.length - 1 || double.parse(text) < _kib) {
      return (unit: unit, text: text);
    }
    value /= _kib;
    unit++;
  }
}

/// A non-negative [value] above bytes: one decimal, whole from [_wholeFrom] up.
///
/// The edge is tested on the *rounded* tenth, so 99.96 (which rounds to
/// `100.0`) prints `100` and not the false precision of `100.0`.
String _scaled(double value) {
  final tenth = value.toStringAsFixed(1);
  return double.parse(tenth) >= _wholeFrom ? value.toStringAsFixed(0) : tenth;
}

double _pow1024(int exponent) {
  var scale = 1.0;
  for (var i = 0; i < exponent; i++) {
    scale *= _kib;
  }
  return scale;
}

/// A rate [formatBytesPerSecond] wrote, as a screen reader should say it:
/// `40.4 megabytes a second`, where `MB/s` would be read letter by letter.
String spokenBytesPerSecond(String rate) {
  const units = {
    ' B/s': ' bytes a second',
    ' KB/s': ' kilobytes a second',
    ' MB/s': ' megabytes a second',
    ' GB/s': ' gigabytes a second',
    ' TB/s': ' terabytes a second',
  };
  final plain = rate.replaceAll('\u00A0', ' ');
  for (final MapEntry(:key, :value) in units.entries) {
    if (plain.endsWith(key)) {
      return '${plain.substring(0, plain.length - key.length)}$value';
    }
  }
  return rate;
}

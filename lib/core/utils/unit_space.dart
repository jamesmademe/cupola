/// The space between a figure and its unit.
///
/// A no-break space (U+00A0), so `4.4 GB`, `4.2 MB/s`, `9 h` and `41 °C` never
/// split across two lines, and a column of them keeps its figures beside their
/// units. Plain space is for words: `12 min ago` breaks before `ago` and
/// nowhere inside `12 min`.
///
/// The rule (the brand book's, `design/system/README.md`, formats) is held by
/// `test/core/utils/unit_space_guard_test.dart`: a literal that puts a plain
/// space between a figure and a unit symbol fails there. It covers unit
/// *symbols* (B, KB/s, Mbps, ms, s, min, h, d, °C). A unit spelled out as a word
/// in a sentence (`3 days`, `6 minutes`) is prose and breaks like prose.
///
/// Not for the percent sign, which is glued to its figure with no space at all
/// (`percent_format.dart`), nor for a compact duration that has no space to
/// begin with (`1h 5m`).
library;

/// U+00A0, the no-break space.
const String unitSpace = '\u00A0';

/// U+2060, the word joiner: no width, and no break on either side of it.
const String wordJoiner = '\u2060';

/// [figure] and [unit] with a no-break space between: `withUnit(4.4, 'GB')`
/// is `4.4 GB`, `withUnit(12, 'min')` is `12 min`.
///
/// A slash in the unit is followed by [wordJoiner]: a line may break after a
/// slash, and `4.2 MB/s` would otherwise end a line with `4.2 MB/` and start
/// the next with `s`.
String withUnit(Object figure, String unit) =>
    '$figure$unitSpace${unit.replaceAll(_bareSlash, '/$wordJoiner')}';

/// A slash not yet followed by [wordJoiner].
final RegExp _bareSlash = RegExp('/(?!$wordJoiner)');

/// Whether [text] ends with a rate (`MB/s`), as [withUnit] writes one.
bool endsWithRate(String text) =>
    text.replaceAll(wordJoiner, '').endsWith('/s');

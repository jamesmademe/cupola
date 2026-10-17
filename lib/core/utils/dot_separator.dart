/// The dot between the parts of a line: `Bluray-1080p · 8.4 GB`,
/// `2 downloading · 18 seeding`.
///
/// A no-break space (U+00A0) before the dot and a plain space after it, so a
/// line that wraps breaks after the dot and the next line starts with a word,
/// never with `·`. The dot stays with the part it follows.
///
/// The rule is held by `test/core/utils/dot_separator_guard_test.dart`: a
/// literal in `lib/` with a plain space before the dot fails there. Inside a
/// longer literal the same spacing is written with the escape:
/// `'$size\u00A0· $age'`.
library;

/// U+00A0, a dot, and a space.
const String dotSeparator = '\u00A0· ';

/// Matches the dot between two parts, spaced either way: a line saved before
/// the no-break space (a last-known Home row) splits the same as a new one.
final RegExp _anySeparator = RegExp('[ \u00A0]· ');

/// [line]'s parts, split at each [dotSeparator] (or at the older ` · `).
List<String> splitParts(String line) => line.split(_anySeparator);

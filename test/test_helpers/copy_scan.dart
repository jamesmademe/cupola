/// The copy of a Dart source file: every string literal a person could read,
/// lexed the way the compiler reads it, for the guards that hold the app's
/// words and figures (`lexicon_guard_test.dart`, `percent_format_guard_test.dart`,
/// `unit_space_guard_test.dart`).
///
/// A source scan that works on lines sees comments, code and identifiers; this
/// one sees only what the app can print. What a [CopyLiteral] is:
///
///  * the literal's text with escapes resolved (`\u00A0` is a no-break space,
///    `\n` a space) and every interpolation replaced by [copyHole];
///  * adjacent literals joined as Dart joins them, so a sentence wrapped across
///    lines is read whole;
///  * never a raw string (a pattern), a directive, or a literal matched against
///    a wire value (see [_isWireValue]).
library;

/// What an interpolation reads as in [CopyLiteral.prose].
const copyHole = '∅';

/// `\uXXXX`, `\u{X…}` or `\xXX`: the three ways Dart writes a character by
/// its code point. The groups are the digits of each form.
final _unicodeEscape = RegExp(
  r'\\(?:u([0-9A-Fa-f]{4})|u\{([0-9A-Fa-f]{1,6})\}|x([0-9A-Fa-f]{2}))',
);

class CopyLiteral {
  CopyLiteral(this.path, this.line, this.prose);

  final String path;
  final int line;

  /// The literal's text with escapes resolved and every interpolation
  /// replaced by [copyHole].
  final String prose;
}

/// Every string literal in [source] that a person could read — see the file
/// comment for what is left out.
List<CopyLiteral> copyOf(String path, String source) {
  final found = <CopyLiteral>[];
  final s = source;

  int lineAt(int offset) => '\n'.allMatches(s.substring(0, offset)).length + 1;
  bool isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

  late int Function(int start, {bool closeBrace}) code;

  // Lexes the literal at [start]: the offset after it, and its prose (null for
  // a raw string, which is a pattern).
  (int, String?) string(int start) {
    var i = start;
    var raw = false;
    if (s[i] == 'r') {
      raw = true;
      i++;
    }
    final quote = s[i];
    final triple = s.startsWith(quote * 3, i);
    final delimiter = triple ? quote * 3 : quote;
    i += delimiter.length;
    final prose = StringBuffer();
    while (i < s.length) {
      if (s.startsWith(delimiter, i)) {
        return (i + delimiter.length, raw ? null : prose.toString());
      }
      final c = s[i];
      if (!raw && c == r'\') {
        // `\u00A0`, `\u{1F4A5}` and `\x41` are the character they name: a
        // no-break space written as an escape must read as one here.
        final unicode = _unicodeEscape.matchAsPrefix(s, i);
        if (unicode != null) {
          final digits =
              unicode.group(1) ?? unicode.group(2) ?? unicode.group(3);
          prose.writeCharCode(int.parse(digits!, radix: 16));
          i = unicode.end;
          continue;
        }
        if (i + 1 < s.length) {
          final next = s[i + 1];
          prose.write(switch (next) {
            'n' || 't' || 'r' => ' ',
            _ => next,
          });
        }
        i += 2;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < s.length) {
        if (s[i + 1] == '{') {
          prose.write(copyHole);
          i = code(i + 2, closeBrace: true);
          continue;
        }
        final ident = RegExp(r'[A-Za-z_]\w*').matchAsPrefix(s, i + 1);
        if (ident != null) {
          prose.write(copyHole);
          i = ident.end;
          continue;
        }
      }
      if (!triple && c == '\n') return (i, raw ? null : prose.toString());
      prose.write(c);
      i++;
    }
    return (i, raw ? null : prose.toString());
  }

  bool opensString(int i) {
    if (i >= s.length) return false;
    final c = s[i];
    if (c == "'" || c == '"') return true;
    return c == 'r' &&
        i + 1 < s.length &&
        (s[i + 1] == "'" || s[i + 1] == '"') &&
        (i == 0 || !isIdent(s[i - 1]));
  }

  // The offset of the next token after [i], past whitespace and comments.
  int skipGap(int i) {
    while (i < s.length) {
      if (s.startsWith('//', i)) {
        final end = s.indexOf('\n', i);
        if (end < 0) return s.length;
        i = end;
        continue;
      }
      if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        i = end < 0 ? s.length : end + 2;
        continue;
      }
      if (s[i].trim().isEmpty) {
        i++;
        continue;
      }
      return i;
    }
    return i;
  }

  // Lexes the literal at [start] and every literal adjacent to it, which Dart
  // joins into one string: a sentence wrapped across lines is read whole, so
  // a banned phrase split at the wrap (`'… try '` `'again.'`) is still seen.
  // Returns the offset after the last of them.
  int strings(int start) {
    var (end, prose) = string(start);
    var raw = prose == null;
    final joined = StringBuffer(prose ?? '');
    var next = skipGap(end);
    while (opensString(next)) {
      final (nextEnd, nextProse) = string(next);
      raw = raw || nextProse == null;
      joined.write(nextProse ?? '');
      end = nextEnd;
      next = skipGap(end);
    }
    if (!raw && !_isWireValue(s, start, end)) {
      found.add(CopyLiteral(path, lineAt(start), joined.toString()));
    }
    return end;
  }

  code = (int start, {bool closeBrace = false}) {
    var i = start;
    var depth = 0;
    while (i < s.length) {
      if (s.startsWith('//', i)) {
        final end = s.indexOf('\n', i);
        if (end < 0) return s.length;
        i = end;
        continue;
      }
      if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        i = end < 0 ? s.length : end + 2;
        continue;
      }
      final c = s[i];
      if (opensString(i)) {
        i = strings(i);
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        if (closeBrace && depth == 0) return i + 1;
        depth--;
      }
      i++;
    }
    return i;
  };

  code(0);
  return found;
}

/// Whether the literal spanning [start]..[end] is matched against a wire value
/// or names code rather than copy. See the file comment.
bool _isWireValue(String s, int start, int end) {
  final lineStart = s.lastIndexOf('\n', start - 1) + 1;
  final before = s.substring(lineStart, start).trimRight();
  final lineEnd = s.indexOf('\n', end);
  final after = s.substring(end, lineEnd < 0 ? s.length : lineEnd);

  if (RegExp(r'^\s*(import|export|part)\b').hasMatch(before)) return true;
  if (RegExp(r'(==|!=|\bcase)$').hasMatch(before)) return true;
  if (RegExp(r'(contains|startsWith|endsWith)\($').hasMatch(before)) {
    return true;
  }
  // An index — `json['IsPaused']` — not a list literal.
  if (RegExp(r'[\w)\]]\[$').hasMatch(before)) return true;
  // A switch pattern (`'paused' =>`, `'a' || 'b' =>`), a map key or a case
  // label (`'Down': …`, `case 'x':`) — the colon straight after the quote,
  // where a ternary's is spaced.
  if (RegExp(r'^\s*(=>|\|\|)').hasMatch(after)) return true;
  if (after.startsWith(':')) return true;
  return false;
}

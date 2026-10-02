/// The code of a Dart source file, for the guards that hold a rule on how the
/// app is written rather than on what it says (`design_contract_guard_test.dart`).
///
/// A guard on a line of text sees comments, string copy and identifiers alike,
/// and a rule's own documentation is full of the very names it forbids
/// (`never AppColors.warning raw`). [codeOf] keeps what the compiler would
/// read as code and nothing else, with every offset and every line number
/// where it was; [callsOf] then reads the calls of one constructor or method
/// out of it, with the named arguments each passes at its own level.
///
/// Copy is the other half and has its own lexer: `copy_scan.dart`.
library;

import 'dart:io';

/// One Dart file under `lib/`: its path, and its code as [codeOf] reads it.
typedef LibCode = ({String path, String code});

/// Every Dart file under `lib/` through [codeOf], for a guard to scan.
///
/// The generated design tokens are left out: they are written by a tool whose
/// own test holds them, and a rule about hand-written code has no business
/// reading them. Paths use `/`, as the other guards' do.
List<LibCode> libCode() => [
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File &&
        file.path.endsWith('.dart') &&
        !file.path.startsWith('lib/core/generated/'))
      (path: file.path, code: codeOf(file.readAsStringSync())),
];

/// [source] with every comment, and the text of every string literal,
/// replaced by spaces.
///
/// Length and line breaks are untouched, so an offset or a line number found
/// in the result is the same in the source. A string keeps its quotes and
/// its `${…}` interpolations, which are code: `'${AppColors.error}'` is still a
/// use of the colour. Raw strings, triple-quoted strings and strings nested
/// inside an interpolation are lexed as Dart lexes them.
String codeOf(String source) {
  final out = source.codeUnits.toList(growable: false);
  final s = source;

  void blank(int from, int to) {
    for (var i = from; i < to && i < out.length; i++) {
      if (out[i] != 0x0A && out[i] != 0x0D) out[i] = 0x20;
    }
  }

  late int Function(int start, {bool closeBrace}) code;

  bool opensString(int i) {
    if (i >= s.length) return false;
    final c = s[i];
    if (c == "'" || c == '"') return true;
    return c == 'r' &&
        i + 1 < s.length &&
        (s[i + 1] == "'" || s[i + 1] == '"') &&
        (i == 0 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(s[i - 1]));
  }

  // The offset after the literal that starts at [start] (on its `r`, if raw,
  // else on its quote), blanking its text and walking its interpolations as
  // code.
  int string(int start) {
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
    var textFrom = i;
    while (i < s.length) {
      if (s.startsWith(delimiter, i)) {
        blank(textFrom, i);
        return i + delimiter.length;
      }
      final c = s[i];
      if (!raw && c == r'\') {
        i += 2;
        continue;
      }
      if (!raw && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
        blank(textFrom, i);
        i = code(i + 2, closeBrace: true);
        textFrom = i;
        continue;
      }
      if (!triple && c == '\n') {
        blank(textFrom, i);
        return i;
      }
      i++;
    }
    blank(textFrom, i);
    return i;
  }

  code = (int start, {bool closeBrace = false}) {
    var i = start;
    var depth = 0;
    while (i < s.length) {
      if (s.startsWith('//', i)) {
        var end = s.indexOf('\n', i);
        if (end < 0) end = s.length;
        blank(i, end);
        i = end;
        continue;
      }
      if (s.startsWith('/*', i)) {
        final close = s.indexOf('*/', i + 2);
        final end = close < 0 ? s.length : close + 2;
        blank(i, end);
        i = end;
        continue;
      }
      if (opensString(i)) {
        i = string(i);
        continue;
      }
      final c = s[i];
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
  return String.fromCharCodes(out);
}

/// One call found by [callsOf]: where it is, and the named arguments it passes
/// at its own level, each with the source text of its value.
class CodeCall {
  const CodeCall(this.path, this.line, this.named);

  final String path;
  final int line;

  /// Argument name to value, as written (whitespace runs collapsed to a space).
  final Map<String, String> named;

  bool names(String argument) => named.containsKey(argument);

  String get where => '$path:$line';
}

/// Every call [opener] matches in [code] (already through [codeOf]). [opener]
/// must end on the call's opening parenthesis: `RegExp(r'\bTextStyle\(')`.
List<CodeCall> callsOf(String path, String code, RegExp opener) {
  final calls = <CodeCall>[];
  for (final match in opener.allMatches(code)) {
    final open = match.end - 1;
    final line = '\n'.allMatches(code.substring(0, open)).length + 1;
    calls.add(CodeCall(path, line, _namedArguments(code, open)));
  }
  return calls;
}

/// The named arguments of the list opened by the `(` at [open]: the
/// `name: value` that each top-level argument may start with. [code] has no
/// comments and no string text, so a bracket or a comma is always code.
Map<String, String> _namedArguments(String code, int open) {
  final named = <String, String>{};
  final label = RegExp(r'^\s*(\w+)\s*:(?!:)([\s\S]*)$');
  var depth = 0;
  var start = open + 1;

  void argumentEndsAt(int end) {
    final hit = label.firstMatch(code.substring(start, end));
    if (hit != null) {
      named[hit.group(1)!] = hit
          .group(2)!
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    }
    start = end + 1;
  }

  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        argumentEndsAt(i);
        break;
      }
    }
    if (c == ',' && depth == 1) argumentEndsAt(i);
  }
  return named;
}

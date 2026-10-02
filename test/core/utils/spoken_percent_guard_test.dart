import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

import '../../test_helpers/copy_scan.dart';

/// A percentage a screen reader says is `62 percent`: units are words, in
/// American English. Never `62%` in a semantics label (a reader says "sixty-two
/// percent sign" or drops it, depending on the verbosity the user chose), and
/// never `per cent`.
///
/// `percent_format.dart` holds the form: [spokenPercent] for a number, and
/// [spokenPercents] for a sentence that was composed from visible strings
/// (`joinSpokenParts` and the stream session value run every part through it).
/// This guard keeps a visible percentage out of a spoken one:
///
///  * **`formatPercent` never sits in a semantics label.** A source scan for
///    each call, and where it stands: inside a `Semantics(` call, in an argument
///    named for what is spoken (`semanticLabel`, `semanticValue`,
///    `semanticHint`, `spoken`), or in a function or getter whose name says it
///    is spoken (`*spoken*`, `*semantic*`, `*RowValue`, `*SessionValue`,
///    `*ForSpeech`). A visible `Text` and a `ServiceKpi.value` are not spoken
///    and may use it.
///  * **No `per cent`** in any copy.
///
/// What it cannot see: a visible string that was formatted somewhere else and
/// handed to a semantics label as it is. The joins that build spoken sentences
/// rewrite a glued percentage on the way for that reason, and the tests below
/// hold them.
void main() {
  const home = 'lib/core/utils/percent_format.dart';
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .where((file) => file.path != home)
      .toList(growable: false);

  test('formatPercent is not used in a semantics label', () {
    final offenders = [
      for (final file in files)
        for (final line in _spokenUses(file.readAsStringSync()))
          '${file.path}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A semantics label says `spokenPercent(value)` (`62 percent`), '
          'never the visible `62%`. A visible Text keeps formatPercent.',
    );
  });

  test('no copy in lib/ says "per cent"', () {
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (RegExp(
            r'\bper cent\b',
            caseSensitive: false,
          ).hasMatch(literal.prose))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'The word is `percent`, in American English: spokenPercent.',
    );
  });

  test('the scan finds a visible percentage in a spoken place', () {
    const planted = r'''
String inFlightRowValue(int p) => [
  '${formatPercent(p)} done',
].join(', ');
Widget a() => Text(formatPercent(p));
Widget b() => Semantics(label: 'Used ${formatPercent(p)}', child: x);
Widget c() => MediaChildTile(semanticLabel: formatPercent(p));
Widget d() => ServiceKpi(label: 'Used', value: formatPercent(p));
class A {
  String get semanticLabel => formatPercent(p);
  static String? _spokenState(Item item) {
    return '${formatPercent(p)} watched';
  }
  Widget build(BuildContext context) {
    return Row(children: [Text(formatPercent(p))]);
  }
}
String shown(int p) => formatPercent(p);
Widget e() => Semantics(label: spokenPercent(p), child: x);
''';
    expect(_spokenUses(planted), [
      2,
      5,
      6,
      9,
      11,
    ], reason: 'the lines of the spoken uses, and no others');
  });

  group('the spoken form', () {
    test(
      'spokenPercent is the figure under the rule, with the sign a word',
      () {
        expect(spokenPercent(62), '62 percent');
        expect(spokenPercent(62.5), '63 percent');
        expect(spokenPercent(62.5, decimals: 1), '62.5 percent');
        // The ear and the eye agree: never 100 before 100.
        expect(spokenPercent(99.6), '99 percent');
        expect(spokenPercent(100), '100 percent');
        expect(spokenPercent(double.nan), 'no percentage');
      },
    );

    test('spokenPercents spells out the glued figures in a sentence', () {
      expect(
        spokenPercents('Dune, 62%, 3 min left'),
        'Dune, 62 percent, 3 min left',
      );
      expect(spokenPercents('99.9% done'), '99.9 percent done');
      expect(spokenPercents('no figure here'), 'no figure here');
      expect(spokenPercents('62% and 18%'), '62 percent and 18 percent');
    });

    test('a spoken sentence composed from visible parts has no % in it', () {
      expect(
        joinSpokenParts(['Sprite Fright', formatPercent(62), 'tv']),
        'Sprite Fright, 62 percent, tv',
      );
      expect(
        spokenFromDotted('4.4 GB · 62% · 3 min left'),
        isNot(contains('%')),
      );
    });
  });
}

/// The 1-based lines of every `formatPercent(` that stands in a spoken place.
List<int> _spokenUses(String source) {
  final code = source
      .split('\n')
      .map((line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');
  final lines = code.split('\n');
  final found = <int>[];
  for (final match in RegExp(r'\bformatPercent\(').allMatches(code)) {
    final line = '\n'.allMatches(code.substring(0, match.start)).length;
    if (_inSpokenCall(code, match.start) ||
        _inSpokenArgument(code, match.start) ||
        _spokenMember.hasMatch(_memberName(lines, line))) {
      found.add(line + 1);
    }
  }
  return found;
}

/// A callee named for what is said (`joinSpokenParts(`, `semanticSummary(`).
final _spokenCallee = RegExp(r'^(?:\w*[Ss]poken\w*|semantic\w*)$');

/// The arguments of `Semantics(` that are said (its `child` is drawn).
const _spokenSemanticsArguments = {
  'label',
  'value',
  'hint',
  'increasedValue',
  'decreasedValue',
  'onTapHint',
  'onLongPressHint',
};

/// Arguments named for what is said, wherever they appear.
final _spokenArgument = RegExp(
  r'^\s*(?:semanticLabel|semanticValue|semanticHint|semanticsLabel|spoken|spokenValue)\s*:',
);

/// Functions and getters named for what is said.
final _spokenMember = RegExp(
  r'[Ss]poken|[Ss]emantic|RowValue|SessionValue|ForSpeech|Announce',
);

/// Whether [index] is said by an enclosing call: inside the `label`, `value`
/// or `hint` of a `Semantics(`, or anywhere inside a call named for speech.
bool _inSpokenCall(String code, int index) {
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final char = code[i];
    if (')]}'.contains(char)) {
      depth++;
    } else if ('([{'.contains(char)) {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (char != '(') continue;
      var start = i;
      while (start > 0 && RegExp(r'\w').hasMatch(code[start - 1])) {
        start--;
      }
      final callee = code.substring(start, i);
      if (callee == 'Semantics') {
        final name = _argumentName(code, i, index);
        if (name != null && _spokenSemanticsArguments.contains(name)) {
          return true;
        }
      } else if (_spokenCallee.hasMatch(callee)) {
        return true;
      }
    }
  }
  return false;
}

/// The name of the argument of the call opened at [open] that holds [index].
String? _argumentName(String code, int open, int index) {
  var depth = 0;
  var argumentStart = open + 1;
  for (var i = open + 1; i < index; i++) {
    final char = code[i];
    if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      depth--;
    } else if (char == ',' && depth == 0) {
      argumentStart = i + 1;
    }
  }
  return RegExp(
    r'^\s*(\w+)\s*:',
  ).firstMatch(code.substring(argumentStart, index))?.group(1);
}

/// Whether the argument holding [index] is named for what is said.
bool _inSpokenArgument(String code, int index) {
  var depth = 0;
  var start = index;
  while (start > 0) {
    final char = code[start - 1];
    if (')]}'.contains(char)) {
      depth++;
    } else if ('([{'.contains(char)) {
      if (depth == 0) break;
      depth--;
    } else if ((char == ',' || char == ';') && depth == 0) {
      break;
    }
    start--;
  }
  return _spokenArgument.hasMatch(code.substring(start, index));
}

/// Words that open a statement, never a declaration.
const _statementWords = {
  'return',
  'await',
  'throw',
  'final',
  'var',
  'const',
  'if',
  'for',
  'while',
  'else',
  'case',
  'switch',
  'yield',
  'assert',
  'new',
};

/// The name of the function, getter or method that holds line [index]: the
/// nearest line above that opens a declaration, which is a line indented at
/// most two that has a type and a name before its first `(` or `=>`.
String _memberName(List<String> lines, int index) {
  for (var i = index; i >= 0; i--) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (line.length - trimmed.length > 2 ||
        !RegExp(r'^[A-Za-z_]').hasMatch(trimmed)) {
      continue;
    }
    final cut = RegExp(r'\(|=>|\{|=').firstMatch(trimmed)?.start;
    final head = (cut == null ? trimmed : trimmed.substring(0, cut)).trim();
    final tokens = head.split(RegExp(r'\s+'));
    if (tokens.length < 2 || _statementWords.contains(tokens.first)) continue;
    return tokens.last;
  }
  return '';
}

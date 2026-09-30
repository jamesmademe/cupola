import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The tone rule's red arm, held on the controls: **red means unreachable and
/// nothing else — a destructive action is never red.** It is a neutral control
/// whose verb says exactly what will happen, and if it cannot be undone, one
/// neutral sentence says so.
///
/// Until 2026-09-30 the app carried an exception — "red on an action means
/// irreversible" — and used both styles at once: some deletes confirmed with a
/// red fill, a red glyph and a red *cannot be undone* banner, others in the
/// theme's own fill, and a few red buttons opened neutral dialogs. The exception
/// is gone, and these scans keep it gone. They are source scans because the
/// regression is one plausible `styleFrom(backgroundColor: …error…)` in a diff,
/// and a bare *Delete* reads as a fine label until twelve of them say it.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  /// Every way the app has of naming red.
  final red = RegExp(
    r'StatusTone\.error\b|colorScheme\.error\b|scheme\.error\b|'
    r'\berrorContainer\b|\bonErrorContainer\b|\bonError\b|AppColors\.error\b',
  );

  /// Source with comment lines blanked, so a doc comment explaining the rule
  /// may name what it forbids. Lines keep their numbers.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');

  int lineAt(String source, int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  /// The argument list opened by the `(` at [open], parentheses balanced.
  String argumentsFrom(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
      }
    }
    return source.substring(open);
  }

  test('lib/ has files to scan', () {
    expect(libFiles, isNotEmpty);
  });

  test('no button style and no dialog is built with red', () {
    // A button's own style, and every dialog built in `lib/`: the confirm, its
    // title glyph and any note under it.
    final opener = RegExp(
      r'\b(?:FilledButton|TextButton|OutlinedButton|ElevatedButton|IconButton)'
      r'\.styleFrom\(|\bButtonStyle\(|\bAlertDialog\(|\bSimpleDialog\(|'
      r'\bshowAppConfirmDialog\(|\bshowAppTypedConfirmDialog\(',
    );
    final offenders = <String>[];
    for (final file in libFiles) {
      final source = codeOf(file);
      for (final match in opener.allMatches(source)) {
        final body = argumentsFrom(source, match.end - 1);
        final hit = red.firstMatch(body);
        if (hit == null) continue;
        offenders.add(
          '${file.path}:${lineAt(source, match.start)}  '
          '${match.group(0)} … ${hit.group(0)}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A button or dialog here is painted with the error colour. Red means '
          'unreachable and nothing else: a delete, a stop or a reset is the '
          "theme's own control, and its confirmation's verb says what happens.",
    );
  });

  test('no delete control is red', () {
    // The glyph a delete wears, and every colour argument near it — an
    // `Icon(color:)`, an `IconButton(color:)`, a `foregroundColor:` — read to
    // the end of its own expression. A status nearby (a *Deleted* badge's
    // glyph mapping) names no colour argument and is left alone.
    final glyph = RegExp(r'Icons\.delete\w*');
    final colourArgument = RegExp(r'\b\w*[cC]olor\s*:');
    final offenders = <String>{};
    for (final file in libFiles) {
      final source = codeOf(file);
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!glyph.hasMatch(lines[i])) continue;
        final from = (i - 6).clamp(0, lines.length);
        final to = (i + 10).clamp(0, lines.length);
        final window = lines.sublist(from, to).join('\n');
        for (final argument in colourArgument.allMatches(window)) {
          // The expression runs to the comma or bracket that closes it.
          var depth = 0;
          var end = argument.end;
          for (; end < window.length; end++) {
            final c = window[end];
            if (c == '(' || c == '[' || c == '{') depth++;
            if (c == ')' || c == ']' || c == '}') {
              if (depth == 0) break;
              depth--;
            }
            if (c == ',' && depth == 0) break;
          }
          final expression = window.substring(argument.start, end);
          if (!red.hasMatch(expression)) continue;
          final line = from + lineAt(window, argument.start);
          offenders.add('${file.path}:$line  ${expression.trim()}');
        }
      }
    }
    expect(
      offenders.toList(),
      isEmpty,
      reason:
          'A delete control is coloured with the error tone. It takes the ink '
          'its neighbours take; the confirmation carries the weight in words.',
    );
  });

  test('every confirm label names what will happen', () {
    // A verb and its object — *Delete job*, *Take down*, *Remove from Radarr*
    // — never a bare verb, and never one of the words that say nothing.
    const vague = {
      'confirm',
      'ok',
      'okay',
      'yes',
      'delete',
      'remove',
      'continue',
      'proceed',
      'done',
      'submit',
      'apply',
      'accept',
      'sure',
    };
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");
    final indent = RegExp(r'^\s*');
    final labels = <(String, String)>[];

    for (final file in libFiles) {
      final lines = codeOf(file).split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final String expression;
        if (line.contains('confirmLabelFor:')) {
          // The closure: every line indented under the argument's own.
          final depth = indent.firstMatch(line)!.group(0)!.length;
          final body = StringBuffer(line);
          for (var j = i + 1; j < lines.length; j++) {
            final next = lines[j];
            if (next.trim().isNotEmpty &&
                indent.firstMatch(next)!.group(0)!.length <= depth) {
              break;
            }
            body.writeln(next);
          }
          expression = body.toString();
        } else if (line.contains('confirmLabel:')) {
          // The expression, which may wrap until the argument's comma.
          final body = StringBuffer(line.split('confirmLabel:').last);
          for (var j = i; !body.toString().trimRight().endsWith(',');) {
            if (++j >= lines.length) break;
            body.writeln(lines[j]);
          }
          expression = body.toString();
        } else {
          continue;
        }
        for (final match in literal.allMatches(expression)) {
          // `checked('deleteFiles')` names an option key, not a label.
          final before = expression.substring(0, match.start).trimRight();
          if (before.endsWith('(')) continue;
          labels.add(('${file.path}:${i + 1}', match.group(1)!));
        }
      }
    }

    expect(labels, isNotEmpty, reason: 'the scan found no labels at all');
    final offenders = [
      for (final (site, label) in labels)
        if (vague.contains(label.trim().toLowerCase()) ||
            label.trim().split(RegExp(r'\s+')).length < 2)
          '$site  "$label"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A confirm label names the action and its object — "Delete job", '
          '"Remove from Radarr", "Stop playback" — so the button says what the '
          'tap does without the title above it.',
    );
  });
}

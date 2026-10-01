import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A failure state's remedy opens a connection's form, so it has to know whose
/// connection it is. This holds every failure state in `lib/` to being told,
/// rather than reading the service off the start of its own words.
///
/// The words worked as a source for as long as every sentence started with
/// the service's title, and they still back the remedy as a documented
/// fallback. They break on the first sentence that starts any other way (a
/// connection the user named, `Anime's queue`), and they cannot tell two
/// Radarrs apart. A source scan because the regression is one call in a diff
/// that leaves the argument out and still draws, with the fallback quietly
/// covering for it.
///
/// A call that truly cannot know its service is listed, by file, in its
/// widget's allow-list with the reason.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  _guard(
    'InlineErrorRetry',
    libFiles,
    RegExp(r'\bInlineErrorRetry(?:\.fixedHeight)?\('),
    definedIn: 'lib/core/widgets/inline_error_retry.dart',
    // None: every section that draws one reads one service.
    allowed: const {},
  );

  _guard(
    'AppErrorState',
    libFiles,
    RegExp(r'\bAppErrorState(?:\.compact)?\('),
    definedIn: 'lib/core/widgets/app_error_state.dart',
    allowed: const {
      'lib/core/widgets/async_value_widget.dart':
          'Handed a display name by each of its callers, never a service, '
          'so it passes `serviceName` on and the fallback reads it.',
      'lib/core/widgets/media_detail_placeholder_view.dart':
          'Handed a display name by the detail pages it stands in for.',
      'lib/core/widgets/interactive_search_sheet.dart':
          'The sheet `showAsync` opens is told a title, not a service.',
      'lib/features/activity/presentation/global_activity_screen.dart':
          'Every configured service at once: no one service failed, and '
          'no one form holds the fix.',
      'lib/features/stream/presentation/widgets/stream_activity_section.dart':
          'Several media servers, all dark. With one, the section draws '
          "that server's own leaf instead.",
    },
  );
}

/// Holds every [opener] call in `lib/` outside [definedIn] to naming its
/// `service:`, except in the files [allowed] lists with the reason.
void _guard(
  String widget,
  List<File> libFiles,
  RegExp opener, {
  required String definedIn,
  required Map<String, String> allowed,
}) {
  group(widget, () {
    final calls = _callsOf(libFiles, opener, definedIn: definedIn);

    test('the scan finds the calls', () {
      expect(calls, isNotEmpty);
    });

    test('every call names its service', () {
      final offenders = [
        for (final call in calls)
          if (!call.names('service') && !allowed.containsKey(call.path))
            call.where,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'A $widget here names no `service:`. Pass the service whose read '
            'failed (and `instanceId:` when the screen knows the connection), '
            'so the remedy opens the right form. If it truly cannot know, '
            'list the file with the reason.',
      );
    });

    test('the allow-list names only calls that still need it', () {
      final stale = [
        for (final path in allowed.keys)
          if (!calls.any((c) => c.path == path && !c.names('service'))) path,
      ];
      expect(stale, isEmpty);
    });
  });
}

/// One call in `lib/`: where it is and the named arguments it passes at its
/// own level.
class _Call {
  const _Call(this.path, this.line, this.named);

  final String path;
  final int line;
  final Set<String> named;

  bool names(String argument) => named.contains(argument);

  String get where => '$path:$line';
}

/// Every call [opener] matches in [files], except the declarations in
/// [definedIn]. Comment lines are blanked first, so a doc comment may name the
/// widget; lines keep their numbers.
List<_Call> _callsOf(
  List<File> files,
  RegExp opener, {
  required String definedIn,
}) {
  final calls = <_Call>[];
  for (final file in files) {
    if (file.path == definedIn) continue;
    final source = file
        .readAsLinesSync()
        .map((line) => line.trimLeft().startsWith('//') ? '' : line)
        .join('\n');
    for (final match in opener.allMatches(source)) {
      final open = match.end - 1;
      final line = '\n'.allMatches(source.substring(0, open)).length + 1;
      calls.add(_Call(file.path, line, _namedArguments(source, open)));
    }
  }
  return calls;
}

/// The named arguments of the argument list opened by the `(` at [open]: the
/// `name:` that starts each top-level argument. Strings are skipped whole, so
/// a bracket or a colon inside one is not read as code.
Set<String> _namedArguments(String source, int open) {
  final names = <String>{};
  final label = RegExp(r'^\s*(\w+)\s*:(?!:)');
  var depth = 0;
  var start = open + 1;
  var i = open;
  void argumentEndsAt(int end) {
    final hit = label.firstMatch(source.substring(start, end));
    if (hit != null) names.add(hit.group(1)!);
    start = end + 1;
  }

  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"') {
      i = _skipString(source, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) {
        argumentEndsAt(i);
        break;
      }
    }
    if (c == ',' && depth == 1) argumentEndsAt(i);
    i++;
  }
  return names;
}

/// The index just past the string literal that starts at [i], interpolations
/// included.
int _skipString(String source, int i) {
  final quote = source[i];
  final triple = source.startsWith(quote * 3, i);
  final raw = i > 0 && source[i - 1] == 'r';
  var j = i + (triple ? 3 : 1);
  while (j < source.length) {
    final c = source[j];
    if (!raw && c == r'\') {
      j += 2;
      continue;
    }
    if (!raw && c == r'$' && source.startsWith('{', j + 1)) {
      j = _skipBlock(source, j + 1);
      continue;
    }
    if (triple ? source.startsWith(quote * 3, j) : c == quote) {
      return j + (triple ? 3 : 1);
    }
    j++;
  }
  return j;
}

/// The index just past the `}` that closes the `{` at [open].
int _skipBlock(String source, int open) {
  var depth = 0;
  var j = open;
  while (j < source.length) {
    final c = source[j];
    if (c == "'" || c == '"') {
      j = _skipString(source, j);
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return j + 1;
    }
    j++;
  }
  return j;
}

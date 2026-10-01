import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A gateway in front of a service is named for what it is (`Cloudflare
/// Access answered instead of Radarr` · *Add a service token*), and those
/// words need the gateway, not only the reason: `accessGateway` alone can say
/// no more than *Something in front of Radarr answered instead of it*. That
/// fallback is for a gateway nothing could identify, never for one a surface
/// knew and did not hand over.
///
/// So every call in `lib/` that turns a reason into words passes `gateway:`,
/// or names a reason that is not the gateway's: a constant such as
/// `ServiceFailureReason.unreachable`, written at the call or held in a
/// `const` of the same file. A surface that holds the failure itself does
/// better still and hands it over (`describeFailureOf`, `failureMessageOf`),
/// which reads the gateway, and the web page, off it.
///
/// A source scan rather than a type because the reason-only words are right
/// for most of their callers (a constant reason has nothing more to say) and
/// the regression is one call in a diff that leaves the argument out and
/// still draws, with the fallback quietly covering for it. The style of
/// `failure_service_guard_test.dart`.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  // Where the reason sits in each call: the first or second positional
  // argument, or the `reason:` named one (null when the call may leave it out).
  const callees = <String, _ReasonAt>{
    'failureLabel': _ReasonAt.positional(0),
    'failureHeadline': _ReasonAt.positional(0),
    'failureRemedy': _ReasonAt.positional(0),
    'describeFailure': _ReasonAt.positional(1),
    'connectionFailureMessage': _ReasonAt.positional(1),
    'FailureRemedy.forReason': _ReasonAt.positional(1),
    'FaultBand.fault': _ReasonAt.named(),
    'describeConnection': _ReasonAt.named(),
  };

  /// Calls that cannot know a gateway, by file, with the reason. None today:
  /// every surface that turns a non-constant reason into words holds the
  /// failure, or the gateway beside the reason.
  const allowed = <String, String>{};

  final calls = <_Call>[];
  for (final file in libFiles) {
    calls.addAll(_callsIn(file.path, file.readAsStringSync(), callees));
  }

  test('the scan finds the calls it guards', () {
    // A scanner that silently found nothing would pass the test below.
    expect(calls.length, greaterThan(40));
  });

  test('every reason turned into words carries its gateway', () {
    final offenders = [
      for (final call in calls)
        if (!call.passes && !allowed.containsKey(call.path))
          '${call.path}:${call.line}  ${call.callee}(…)',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'These turn a reason into words without the gateway, so a gateway '
          'in front of the service reads "Something in front of it answered". '
          'Hand over the failure (describeFailureOf, failureMessageOf) or '
          'pass gateway: accessGatewayOf(error). A call that truly cannot know '
          'one goes in `allowed` with its reason.',
    );
  });

  test('the allow-list names files that still need it', () {
    final stale = [
      for (final path in allowed.keys)
        if (!calls.any((call) => call.path == path && !call.passes)) path,
    ];
    expect(stale, isEmpty, reason: 'Remove these from `allowed`.');
  });
}

class _ReasonAt {
  const _ReasonAt.positional(int this.index) : named = false;
  const _ReasonAt.named() : index = null, named = true;

  final int? index;
  final bool named;
}

class _Call {
  _Call(this.path, this.line, this.callee, this.passes);

  final String path;
  final int line;
  final String callee;
  final bool passes;
}

Iterable<_Call> _callsIn(
  String path,
  String source,
  Map<String, _ReasonAt> callees,
) sync* {
  // `const _reason = ServiceFailureReason.insecureTransport;` and the like:
  // a name that is a constant reason.
  final constants = <String, String>{
    for (final match in RegExp(
      r'const\s+(\w+)\s*=\s*ServiceFailureReason\.(\w+)\s*;',
    ).allMatches(source))
      match.group(1)!: match.group(2)!,
  };

  for (final MapEntry(key: callee, value: at) in callees.entries) {
    final pattern = RegExp('(?<![\\w.])${RegExp.escape(callee)}\\(');
    for (final match in pattern.allMatches(source)) {
      final lineStart = source.lastIndexOf('\n', match.start) + 1;
      final before = source.substring(lineStart, match.start);
      // A comment, or the declaration itself.
      if (before.trimLeft().startsWith('//')) continue;
      if (RegExp(
        r'(^|\s)(String\??|FailurePresentation|ConnectionPresentation|'
        r'FailureRemedy\?|factory|static)\s+$',
      ).hasMatch(before)) {
        continue;
      }
      final args = _arguments(source, match.end);
      if (args == null) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      yield _Call(path, line, callee, _passes(args, at, constants));
    }
  }
}

bool _passes(List<String> args, _ReasonAt at, Map<String, String> constants) {
  if (args.any((a) => a.trimLeft().startsWith('gateway:'))) return true;
  final String? reason;
  if (at.named) {
    final named = args.where((a) => a.trimLeft().startsWith('reason:'));
    if (named.isEmpty) return true; // No reason, nothing to name.
    reason = named.first.trimLeft().substring('reason:'.length).trim();
  } else {
    final positional = [
      for (final a in args)
        if (!RegExp(r'^\s*\w+\s*:(?!:)').hasMatch(a)) a.trim(),
    ];
    if (positional.length <= at.index!) return true;
    reason = positional[at.index!];
  }
  final literal = RegExp(r'^ServiceFailureReason\.(\w+)$').firstMatch(reason);
  final constant = constants[reason];
  final name = literal?.group(1) ?? constant;
  return name != null && name != 'accessGateway';
}

/// The top-level arguments of the call whose `(` ends at [open], or null when
/// it cannot be read.
List<String>? _arguments(String source, int open) {
  var depth = 1;
  var start = open;
  final args = <String>[];
  String? quote;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (quote != null) {
      if (char == '\\') {
        i++;
      } else if (source.startsWith(quote, i)) {
        i += quote.length - 1;
        quote = null;
      }
      continue;
    }
    if (source.startsWith("'''", i) || source.startsWith('"""', i)) {
      quote = source.substring(i, i + 3);
      i += 2;
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      continue;
    }
    if (char == '(' || char == '[' || char == '{') depth++;
    if (char == ')' || char == ']' || char == '}') {
      depth--;
      if (depth == 0) {
        final last = source.substring(start, i);
        if (last.trim().isNotEmpty) args.add(last);
        return args;
      }
    }
    if (char == ',' && depth == 1) {
      args.add(source.substring(start, i));
      start = i + 1;
    }
  }
  return null;
}

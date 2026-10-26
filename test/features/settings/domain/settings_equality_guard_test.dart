/// Every field of a connection's value classes is in its `==` and `hashCode`.
///
/// Settings are saved by difference (`SettingsService.saveSettings` with
/// `previous`): a connection equal to the one last written is not written at
/// all. A field left out of `==` is therefore a change that is skipped in
/// silence, and when the field is a credential, a secret that never reaches
/// the Keychain. Adding a field to one of these classes means adding it to
/// both, or this test fails.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/code_scan.dart';

typedef _Target = ({String file, String className});

const _targets = <_Target>[
  (
    file: 'lib/features/settings/domain/service_instance.dart',
    className: 'ServiceInstance',
  ),
  (
    file: 'lib/features/settings/domain/connection_address.dart',
    className: 'ConnectionAddress',
  ),
  (
    file: 'lib/features/settings/domain/connection_access.dart',
    className: 'NoAccess',
  ),
  (
    file: 'lib/features/settings/domain/connection_access.dart',
    className: 'CloudflareServiceToken',
  ),
  (
    file: 'lib/features/settings/domain/connection_access.dart',
    className: 'ProxyPassword',
  ),
  (
    file: 'lib/features/settings/domain/connection_access.dart',
    className: 'CustomHeaders',
  ),
  (
    file: 'lib/features/discover/domain/seerr_sign_in.dart',
    className: 'SeerrApiKeySignIn',
  ),
  (
    file: 'lib/features/discover/domain/seerr_sign_in.dart',
    className: 'SeerrAccountSignIn',
  ),
];

/// The index just past the group opened at [open] (a `(` or a `{`).
int _past(String code, int open) {
  const pairs = {'(': ')', '{': '}'};
  final opener = code[open];
  final closer = pairs[opener]!;
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == opener) depth++;
    if (code[i] == closer && --depth == 0) return i + 1;
  }
  throw StateError('unbalanced $opener');
}

/// The body of the class [name]: between its braces.
String _classBody(String code, String name) {
  final head = RegExp('class $name\\b[^{]*\\{').firstMatch(code);
  if (head == null) throw StateError('class $name not found');
  final open = head.end - 1;
  return code.substring(open + 1, _past(code, open) - 1);
}

/// What follows [keyword] up to the end of its body: a block, or an arrow
/// ending at the next `;`.
String _bodyAfter(String body, int from) {
  var i = from;
  if (body[i] == '(') i = _past(body, i);
  while (body[i] == ' ' || body[i] == '\n') {
    i++;
  }
  if (body[i] == '{') return body.substring(i, _past(body, i));
  return body.substring(i, body.indexOf(';', i));
}

/// The instance fields of [body]: `final T name;` at the top level of the
/// class, never a static or a local.
List<String> _fields(String body) {
  final fields = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == '{' || c == '(') depth++;
    if (c == '}' || c == ')') depth--;
    if (depth == 0 && c == ';') {
      final statement = body.substring(start, i).trim();
      final match = RegExp(
        r'^final\s+[\w<>?,\s().]+?\s+(\w+)$',
        dotAll: true,
      ).firstMatch(statement);
      if (match != null && !statement.startsWith('static')) {
        fields.add(match.group(1)!);
      }
      start = i + 1;
    } else if (depth == 0 && c == '}') {
      start = i + 1;
    }
  }
  return fields;
}

void main() {
  for (final target in _targets) {
    test('${target.className}: every field is in == and in hashCode', () {
      final code = codeOf(File(target.file).readAsStringSync());
      final body = _classBody(code, target.className);
      final fields = _fields(body);

      final equals = RegExp(r'operator\s*==').firstMatch(body);
      final hash = RegExp(r'\bhashCode\b').firstMatch(body);
      expect(equals, isNotNull, reason: '${target.className} has no ==');
      expect(hash, isNotNull, reason: '${target.className} has no hashCode');
      final inEquals = _bodyAfter(body, equals!.end);
      final inHash = _bodyAfter(body, hash!.end + _skipGetter(body, hash.end));

      for (final field in fields) {
        final word = RegExp('\\b$field\\b');
        expect(
          word.hasMatch(inEquals),
          isTrue,
          reason:
              '${target.className}.$field is missing from ==: a connection '
              'that differs only there reads as unchanged, and saving by '
              'difference would never write it',
        );
        expect(
          word.hasMatch(inHash),
          isTrue,
          reason: '${target.className}.$field is missing from hashCode',
        );
      }
    });
  }

  test('the guard reads fields at all', () {
    final code = codeOf(
      File(
        'lib/features/settings/domain/service_instance.dart',
      ).readAsStringSync(),
    );
    expect(
      _fields(_classBody(code, 'ServiceInstance')),
      containsAll(['id', 'credential', 'access', 'account', 'away']),
    );
  });
}

/// Spaces between `hashCode` and its `=>` or `{`.
int _skipGetter(String body, int from) {
  var i = from;
  while (body[i] == ' ') {
    i++;
  }
  return i - from;
}

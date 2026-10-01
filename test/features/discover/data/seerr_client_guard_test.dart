import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A Seerr client is born in one place, `seerrClientFor`
/// (`lib/features/discover/data/seerr_session.dart`).
///
/// Seerr owes a CSRF token on every write when its protection is on. A
/// client built anywhere else does not send one, and every write it makes is
/// refused as if the key were wrong. A source scan, because that regression is one construction in
/// a diff that works on a server with neither.
///
/// Read for each construction: every `ApiClient(` and
/// `ApiClient.authenticatedBy(` in `lib/` is listed in [_apiClientSites]
/// with the services it builds, and none is Seerr's outside the session
/// file; every `SeerrService(` takes a client from the Seerr constructor;
/// and `watchApiClient` is never asked for Seerr.
void main() {
  final libFiles = {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') &&
          !file.path.startsWith('lib/core/generated/'))
        file.path: _withoutComments(file.readAsStringSync()),
  };

  final apiClients = [
    for (final MapEntry(key: path, value: code) in libFiles.entries)
      ..._callsIn(path, code, _apiClientOpener),
  ];
  final seerrServices = [
    for (final MapEntry(key: path, value: code) in libFiles.entries)
      ..._callsIn(path, code, RegExp(r'(?<!\w)SeerrService\(')),
  ];

  test('there are constructions to read', () {
    expect(apiClients.length, greaterThan(5));
    expect(seerrServices.length, greaterThanOrEqualTo(4));
  });

  test('every ApiClient is built where it is known whose it is', () {
    final unknown = [
      for (final call in apiClients)
        if (!_apiClientSites.containsKey(call.path))
          '${call.path}:${call.line}',
    ];
    expect(
      unknown,
      isEmpty,
      reason:
          'A new ApiClient construction. If it can reach Seerr, build it '
          'with seerrClientFor instead; otherwise list the file in '
          '_apiClientSites with the services it builds.',
    );
  });

  test('every listed ApiClient site still builds one', () {
    final paths = apiClients.map((call) => call.path).toSet();
    expect(
      _apiClientSites.keys.where((path) => !paths.contains(path)),
      isEmpty,
    );
  });

  test('every SeerrService takes the Seerr constructor\'s client', () {
    final offenders = [
      for (final call in seerrServices)
        if (!_seerrConstructors.any(call.declaration.contains))
          '${call.path}:${call.line}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A SeerrService built over a client that did not come from '
          'seerrClientFor (or watchSeerrClient, or the probe\'s '
          'seerrClientFactoryProvider).',
    );
  });

  test('watchApiClient is never asked for Seerr', () {
    final offenders = [
      for (final MapEntry(key: path, value: code) in libFiles.entries)
        for (final match in RegExp(
          r'watchApiClient\(\s*ref,\s*ServiceKey\.seerr',
        ).allMatches(code))
          '$path:${_lineOf(code, match.start)}',
    ];
    expect(offenders, isEmpty);
  });
}

const _sessionFile = 'lib/features/discover/data/seerr_session.dart';

/// Where an `ApiClient` is built, and whose it is.
const _apiClientSites = <String, String>{
  _sessionFile: 'Seerr, the only place, with the CSRF interceptor.',
  'lib/features/settings/data/settings_provider.dart':
      'watchApiClient, for the X-Api-Key services, which asserts it is never '
      'Seerr.',
  'lib/features/settings/data/service_verification.dart':
      'The connection test of the X-Api-Key services, which asserts it is '
      'never Seerr: Seerr has its own branch with seerrClientFor.',
  'lib/features/services/presentation/services_provider.dart':
      'The probe client of the X-Api-Key services; the Seerr branch builds '
      'its own through seerrClientFactoryProvider first.',
  'lib/features/jellyfin/data/jellyfin_client.dart': 'Jellyfin.',
  'lib/features/plex/data/plex_client.dart': 'Plex.',
};

/// What a `SeerrService` may be built over.
const _seerrConstructors = [
  'seerrClientFor(',
  'watchSeerrClient(',
  'seerrClientFactoryProvider',
];

final _apiClientOpener = RegExp(r'(?<!\w)ApiClient(\.authenticatedBy)?\(');

typedef _Call = ({String path, int line, String declaration});

/// The calls [opener] matches in [code], each with the top-level declaration
/// it sits in. A declaration (`ApiClient({`, `SeerrService(this._client`) is
/// not a call.
Iterable<_Call> _callsIn(String path, String code, RegExp opener) sync* {
  for (final match in opener.allMatches(code)) {
    final rest = code.substring(match.end).trimLeft();
    if (rest.startsWith('{') || rest.startsWith('this.')) continue;
    // `ApiClient._(` and the like: a redirecting constructor's own name.
    if (code.substring(0, match.start).endsWith(': this.')) continue;
    yield (
      path: path,
      line: _lineOf(code, match.start),
      declaration: _declarationAround(code, match.start),
    );
  }
}

int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// The top-level declaration [offset] sits in: from the last line that
/// starts at the margin with a name, to the next one.
String _declarationAround(String code, int offset) {
  final lines = code.split('\n');
  final at = _lineOf(code, offset) - 1;
  bool opens(String line) => RegExp(r'^[A-Za-z_@]').hasMatch(line);
  var start = at;
  while (start > 0 && !opens(lines[start])) {
    start--;
  }
  var end = at + 1;
  while (end < lines.length && !opens(lines[end])) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

/// [source] with every `//` comment line blanked, line breaks kept.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

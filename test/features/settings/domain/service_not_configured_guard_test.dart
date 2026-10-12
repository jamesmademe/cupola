import 'dart:io';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:flutter_test/flutter_test.dart';

/// A service nobody set up is **one type, recognised by type**:
/// `ServiceNotConfigured`, never an `Exception` whose words are matched.
///
/// The app used to throw `Exception('<Service> not configured')` from every
/// client provider and find it again with `toString().contains(...)` in eight
/// places. A rewording of one throw silently sent that service's pages to the
/// error card with a Retry that can never succeed, and any server error whose
/// text happened to carry the phrase was drawn as an invitation to set up a
/// service that was set up. A source scan, because either regression is one
/// plausible line in a diff. Comments are skipped: a doc may quote the words.
void main() {
  final files = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  test('lib/ has code to scan', () {
    expect(files.length, greaterThan(300));
  });

  test('nothing throws the words or matches them', () {
    final offenders = [
      for (final file in files) ..._hitsIn(file.path, file.readAsStringSync()),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Throw ServiceNotConfigured(ServiceKey.x) and test for it with '
          '`is ServiceNotConfigured`, never by its text.',
    );
  });

  test('the type still prints the words, for logs and tests', () {
    expect(
      const ServiceNotConfigured(ServiceKey.radarr).toString(),
      'Radarr not configured',
    );
  });

  group('the matcher', () {
    test('catches a thrown phrase and a text match, and passes the type', () {
      const planted = '''
throw Exception('Radarr not configured');
throw Exception("\${service.title} not configured");
if (error.toString().contains('not configured')) {}
if (error is ServiceNotConfigured) {}
throw const ServiceNotConfigured(ServiceKey.radarr);
// throw Exception('Radarr not configured');
/// Used to match `contains('not configured')`.
''';
      expect(_hitsIn('lib/zz_planted.dart', planted), [
        "lib/zz_planted.dart:1  throw Exception('Radarr not configured');",
        'lib/zz_planted.dart:2  throw Exception("\${service.title} not configured");',
        "lib/zz_planted.dart:3  if (error.toString().contains('not configured')) {}",
      ]);
    });
  });
}

final _forbidden = RegExp(
  r'''(?:Exception|contains)\(\s*['"][^'"]*not configured''',
);

List<String> _hitsIn(String path, String source) {
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (!lines[i].trimLeft().startsWith('//') &&
          _forbidden.hasMatch(lines[i]))
        '$path:${i + 1}  ${lines[i].trim()}',
  ];
}

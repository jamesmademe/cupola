import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The lists of Seerr's requests with titles derive from the rows
/// (`requestRowsProvider`, `requestRowsForProvider`): dropping a derived list
/// on its own reads the titles again over rows that were not read again, and
/// leaves the list as old as it was. The one way to drop them is
/// `invalidateSeerrRequests` / `invalidateSeerrRequestsOf`.
void main() {
  final direct = RegExp(
    r'\b(invalidate|refresh)\(\s*'
    r'(requestsProvider|requestsForProvider|servicesRequestsProvider)\b',
  );

  test('nothing in lib/ drops a list of requests with titles by itself', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity.readAsStringSync();
      for (final match in direct.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Drop the rows through invalidateSeerrRequests or '
          'invalidateSeerrRequestsOf (discover_provider.dart).',
    );
  });

  test('the sources a pull drops are the rows, never the derived lists', () {
    final dropped = [
      ...dashboardSourcesOf(ServiceKey.seerr),
      ...serviceKpiSources(ServiceKey.seerr),
    ];
    expect(dropped, contains(requestRowsProvider));
    expect(dropped, isNot(contains(requestsProvider)));
    expect(dropped, isNot(contains(requestsForProvider)));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 8, 20, 40);

ArrHistoryEntry _import(
  String title, {
  required Duration ago,
  required int tmdbId,
  String instanceId = 'radarr',
  String? connectionName,
}) => ArrHistoryEntry(
  service: ServiceKey.radarr,
  id: tmdbId,
  mediaId: tmdbId,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(ago),
  reason: null,
  instanceId: instanceId,
  connectionName: connectionName,
  tmdbId: tmdbId,
);

/// Arrived on the Home: a week of imports, one card per title.
void main() {
  Future<void> pump(WidgetTester tester, ArrHistory history) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.radarr],
          ),
          arrivalsClockProvider.overrideWithValue(() => _now),
          servicesArrivalsProvider.overrideWith((ref) async => history),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: HomeArrivedModule()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one card per title, the newest first, under how many '
      'arrived in the week', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, (
      entries: [
        _import('Sintel', ago: const Duration(days: 3), tmdbId: 2),
        _import(
          'Spring',
          ago: const Duration(hours: 2),
          tmdbId: 1,
          connectionName: '4K',
        ),
        _import('Spring', ago: const Duration(days: 1), tmdbId: 1),
      ],
      coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
    ));

    expect(find.text('Last 7 days\u00A0· 2 new'), findsOne);
    expect(find.text('2\u00A0h ago\u00A0· Radarr 4K'), findsOne);
    expect(
      tester.getTopLeft(find.text('Spring')).dx,
      lessThan(tester.getTopLeft(find.text('Sintel')).dx),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Spring, 2\u00A0h ago, Radarr 4K$')),
      findsOne,
    );
    handle.dispose();
  });

  testWidgets('a library silent: the count says who it is from, and the '
      'silent one is named', (tester) async {
    await pump(tester, (
      entries: [_import('Sintel', ago: const Duration(days: 3), tmdbId: 2)],
      coverage: SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, instanceId: 'radarr'),
        SourceCoverage.failure(
          ServiceKey.radarr,
          const ClassifiedFailure(ServiceFailureReason.unreachable),
          instanceId: 'radarr-4k',
          name: '4K',
        ),
      ]),
    ));
    expect(find.text('Last 7 days\u00A0· 1 from Radarr'), findsOne);
    expect(find.textContaining('Radarr 4K did not answer'), findsOne);
  });

  testWidgets('nothing arrived and every library answered: no module', (
    tester,
  ) async {
    await pump(tester, (
      entries: [_import('Old', ago: const Duration(days: 9), tmdbId: 3)],
      coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
    ));
    expect(find.text('Arrived'), findsNothing);
  });
}

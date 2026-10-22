/// What NZBGet's Overview says failed today leads to the History tab, which
/// lists it; several failures are one row, and a job that finished as asked is
/// only read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/settings_scope.dart';

DateTime _todayAt(double fraction) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  return midnight.add(
    Duration(
      microseconds: (now.difference(midnight).inMicroseconds * fraction)
          .round(),
    ),
  );
}

NzbgetHistoryItem _item(
  String name,
  double at, {
  String status = 'SUCCESS/ALL',
}) => NzbgetHistoryItem(
  id: name.hashCode,
  name: name,
  status: status,
  category: 'tv',
  time: _todayAt(at),
);

Future<OverviewShell> _pump(
  WidgetTester tester,
  List<NzbgetHistoryItem> history,
) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final shell = OverviewShell(
    ServiceKey.nzbget,
    const NzbgetOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWith(nzbgetUrl: 'http://nzbget.local:6789'),
        ),
        serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: ServiceSummaryStatus.online,
            host: 'nzbget.local:6789',
            version: '21.1',
          ),
        ),
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
        nzbgetStatusProvider.overrideWith(
          (ref) async => const NzbgetStatus(
            downloadRateBytes: 0,
            remainingSizeMb: 0,
            paused: false,
          ),
        ),
        nzbgetQueueProvider.overrideWith((ref) async => const []),
        nzbgetHistoryProvider.overrideWith((ref) async => history),
      ],
      child: shell.app,
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('one failed job is a door to the History tab that lists it, and '
      'a job that finished as asked is only read', (tester) async {
    final shell = await _pump(tester, [
      _item('Andor.S02E02', 0.25),
      _item('Sugar.S02E01', 0.5, status: 'FAILURE/PAR'),
    ]);

    expect(
      find.semantics.byLabel(RegExp(r'^Sugar\.S02E01, failed, par repair')),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens the NZBGet History tab',
      ),
    );
    expect(
      find.semantics.byLabel(RegExp(r'^Andor\.S02E02, success')),
      isSemantics(isButton: false, hasTapAction: false),
    );

    await tester.tap(find.textContaining('Sugar.S02E01'));
    await tester.pumpAndSettle();
    expect(shell.tab, ServiceTab.history);
  });

  testWidgets('three failed jobs are one row, and the header still counts '
      'three', (tester) async {
    final shell = await _pump(tester, [
      _item('Andor.S02E02', 0.2),
      _item('Sugar.S02E01', 0.3, status: 'FAILURE/PAR'),
      _item('Slow.Horses.S04E01', 0.4, status: 'FAILURE/UNPACK'),
      _item('Severance.S02E03', 0.5, status: 'URL_FAILURE'),
    ]);

    expect(find.text('3 downloads failed'), findsOneWidget);
    expect(find.textContaining('· failed'), findsNothing);
    // Newest first, as the rows are.
    expect(
      find.text('Severance.S02E03, Slow.Horses.S04E01, Sugar.S02E01'),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(RegExp(r'^3 downloads failed, ')),
      isSemantics(isButton: true, hint: 'opens the NZBGet History tab'),
    );
    expect(
      tester
          .widget<SectionHeader>(find.widgetWithText(SectionHeader, 'History'))
          .subtitle,
      'today\u00A0· 1 completed\u00A0· 3 failed',
    );

    await tester.tap(find.text('3 downloads failed'));
    await tester.pumpAndSettle();
    expect(shell.tab, ServiceTab.history);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(nzbgetUrl: 'http://nzbget.local:6789');

/// See the SABnzbd screen test: `FilledButton.tonalIcon` builds a private
/// subclass, which `find.byType` cannot see.
Finder _buttonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

List<Override> _ambient({List<NzbgetGroup> queue = const []}) => [
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'nzbget.local:6789',
      version: '21.1',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  nzbgetQueueProvider.overrideWith((ref) async => queue),
  nzbgetHistoryProvider.overrideWith(
    (ref) async => const <NzbgetHistoryItem>[],
  ),
];

void main() {
  testWidgets('an unconfigured NZBGet renders the shared placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
  });

  testWidgets('the pause toggle is inert until the status is known', (
    tester,
  ) async {
    // Regression: `asData?.value.paused ?? false` rendered "Pause all" for the
    // whole first load, so a tap in that window sent `pausedownload()` to a
    // client that was already paused.
    final gate = Completer<NzbgetStatus>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          nzbgetStatusProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );
    await tester.pump();

    final toggle = _buttonWithText('Pause all');
    expect(toggle, findsOneWidget);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);

    gate.complete(
      const NzbgetStatus(
        downloadRateBytes: 0,
        remainingSizeMb: 0,
        paused: true,
      ),
    );
    await tester.pumpAndSettle();

    final resume = _buttonWithText('Resume all');
    expect(resume, findsOneWidget);
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
  });

  testWidgets('a job nobody measured draws no bar and says so', (tester) async {
    // Regression: `remainingSizeMb` defaulted to 0, so a job whose remaining
    // size NZBGet never reported computed `(size - 0) / size` == 1 and drew a
    // full progress bar — a percentage nobody computed, presented as finished.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(
            queue: [
              NzbgetGroup.fromJson(const {
                'NZBID': 7,
                'NZBName': 'Unmeasured.Job',
                'Status': 'DOWNLOADING',
                'Category': 'tv',
                'FileSizeMB': 4800,
              }),
            ],
          ),
          nzbgetStatusProvider.overrideWith(
            (ref) async => const NzbgetStatus(
              downloadRateBytes: 0,
              remainingSizeMb: 0,
              paused: false,
            ),
          ),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unmeasured.Job'), findsOneWidget);
    // No bar at all, rather than a full one.
    expect(
      find.descendant(
        of: find.byType(DownloadQueueTile),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.text('100%'), findsNothing);
    // And the row says why there is nothing to draw.
    expect(find.textContaining('progress unknown'), findsOneWidget);
  });
}

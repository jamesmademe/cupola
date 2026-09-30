import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
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

List<Override> _ambient({
  List<NzbgetGroup> queue = const [],
  bool withQueue = true,
}) => [
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'nzbget.local:6789',
      version: '21.1',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  if (withQueue) nzbgetQueueProvider.overrideWith((ref) async => queue),
  nzbgetHistoryProvider.overrideWith(
    (ref) async => const <NzbgetHistoryItem>[],
  ),
];

NzbgetGroup _group(int id) => NzbgetGroup.fromJson({
  'NZBID': id,
  'NZBName': 'Job.$id',
  'Status': 'DOWNLOADING',
  'Category': 'tv',
  'FileSizeMB': 4800,
  'RemainingSizeMB': 2400,
});

const _status = NzbgetStatus(
  downloadRateBytes: 0,
  remainingSizeMb: 0,
  paused: false,
);

/// Records which jobs NZBGet was asked to delete.
class _DeletingNzbget implements NzbgetClient {
  final deleted = <int>[];

  @override
  Future<bool> deleteGroup(int nzbId) async {
    deleted.add(nzbId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? _queueSubtitle(WidgetTester tester) => tester
    .widget<SectionHeader>(
      find.byWidgetPredicate(
        (w) => w is SectionHeader && w.title == 'Downloading',
      ),
    )
    .subtitle;

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

  // OPS-02. The Queue tab drew `take(5)` groups with no count and no way to
  // reach the rest; `listgroups` had already returned every one of them.
  group('the Queue tab is the whole queue', () {
    test('the header count states the count, or nothing', () {
      expect(nzbgetQueueCountLabel(null), isNull);
      expect(nzbgetQueueCountLabel(0), '0 jobs');
      expect(nzbgetQueueCountLabel(1), '1 job');
      expect(nzbgetQueueCountLabel(8), '8 jobs');
    });

    testWidgets('every group is a reachable row, and the header counts them', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(queue: [for (var i = 1; i <= 8; i++) _group(i)]),
            nzbgetStatusProvider.overrideWith((ref) async => _status),
          ],
          child: const MaterialApp(home: NzbgetScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(_queueSubtitle(tester), '8 jobs');
      final list = find.byType(Scrollable).first;
      for (final name in ['Job.6', 'Job.7', 'Job.8']) {
        await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
        expect(find.text(name), findsOneWidget);
      }
      expect(
        find.byWidgetPredicate(
          (w) => w is SectionHeader && w.title == 'History',
          skipOffstage: false,
        ),
        findsNothing,
      );
    });

    testWidgets('a queue still loading states no count, never zero', (
      tester,
    ) async {
      final gate = Completer<List<NzbgetGroup>>();
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(withQueue: false),
            nzbgetQueueProvider.overrideWith((ref) => gate.future),
            nzbgetStatusProvider.overrideWith((ref) async => _status),
          ],
          child: const MaterialApp(home: NzbgetScreen()),
        ),
      );
      await tester.pump();

      expect(_queueSubtitle(tester), isNull);
      expect(find.textContaining('0 jobs'), findsNothing);

      gate.complete(const []);
      await tester.pumpAndSettle();
      expect(_queueSubtitle(tester), '0 jobs');
    });
  });

  testWidgets('deleting a job asks first, and only a confirm sends it', (
    tester,
  ) async {
    // It fired on the menu tap and toasted "Job removed". No files question
    // here: `GroupDelete` is documented only as "delete and put to history".
    final client = _DeletingNzbget();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(queue: [_group(12)]),
          nzbgetClientProvider.overrideWith((ref) => client),
          nzbgetStatusProvider.overrideWith((ref) async => _status),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openDelete() async {
      await tester.tap(find.byTooltip('Job actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete job'));
      await tester.pumpAndSettle();
    }

    await openDelete();
    expect(find.text('Delete this job?'), findsOneWidget);
    expect(
      find.textContaining('NZBGet moves it to its history'),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.deleted, isEmpty);

    await openDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete job'));
    await tester.pumpAndSettle();
    expect(client.deleted, [12]);
    expect(find.text('Job removed'), findsOneWidget);
  });
}

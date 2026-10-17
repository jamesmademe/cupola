import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/fault_band.dart';
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
import 'package:cupola/features/settings/domain/service_key.dart';
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

NzbgetGroup _group(int id, {String status = 'DOWNLOADING'}) =>
    NzbgetGroup.fromJson({
      'NZBID': id,
      'NZBName': 'Job.$id',
      'Status': status,
      'Category': 'tv',
      'FileSizeMB': 4800,
      'RemainingSizeMB': 2400,
    });

const _status = NzbgetStatus(
  downloadRateBytes: 0,
  remainingSizeMb: 0,
  paused: false,
);

/// An NZBGet that answers `listgroups` with a fixed queue.
class _ListingNzbget implements NzbgetClient {
  _ListingNzbget(this.groups);

  final List<NzbgetGroup> groups;

  @override
  Future<List<NzbgetGroup>> listGroups() async => groups;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      find.byWidgetPredicate((w) => w is SectionHeader && w.title == 'Queue'),
    )
    .subtitle;

void main() {
  testWidgets('the queue reads itself again every three seconds while it is '
      'on screen', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(withQueue: false),
          nzbgetQueueProvider.overrideWith((ref) async {
            reads++;
            return const <NzbgetGroup>[];
          }),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final first = reads;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(reads, greaterThan(first));
    // Leaving the page drops the watch, and the timer with it.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    final after = reads;
    await tester.pump(const Duration(seconds: 6));
    expect(reads, after);
  });

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

    final toggle = _buttonWithText('Stop all');
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
    // full progress bar: a percentage nobody computed, presented as finished.
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

    testWidgets('a row says its stage in the app\'s words, never NZBGet\'s', (
      tester,
    ) async {
      // NZBGet answers `DOWNLOADING`, `PAUSED`, `PP_QUEUED`: shouted, and the
      // middle one a word the brand book bans. The row says what the Overview
      // says, in sentence case where it heads the line.
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(
              queue: [
                _group(1),
                _group(2, status: 'PAUSED'),
                _group(3, status: 'PP_QUEUED'),
              ],
            ),
            nzbgetStatusProvider.overrideWith((ref) async => _status),
          ],
          child: const MaterialApp(home: NzbgetScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('DOWNLOADING'), findsNothing);
      expect(find.textContaining('PAUSED'), findsNothing);
      expect(
        find.textContaining('Downloading\u00A0· tv\u00A0· '),
        findsOneWidget,
      );
      expect(find.textContaining('Stopped\u00A0· tv\u00A0· '), findsOneWidget);
      expect(
        find.textContaining('Post-processing\u00A0· tv\u00A0· '),
        findsOneWidget,
      );
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

  // The rows kept under a fault band used to go on printing what is left as if
  // it were counting down; they say how old the read is instead.
  group('a queue read before the failure', () {
    final readAt = DateTime(2026, 10, 12, 9);
    final key = queueReadKey(
      ServiceKey.nzbget,
      _configured.primaryOf(ServiceKey.nzbget)!.id,
    );
    // The remaining size: the figure that stops counting. The state and the
    // category before it stay under the band.
    const counting = '2.3\u00A0GB';
    final probeDown = StateProvider<bool>((ref) => false);
    late DateTime now;

    Future<ProviderContainer> pumpScreen(
      WidgetTester tester, {
      required bool recorded,
    }) async {
      now = readAt;
      final queue = [_group(1)];
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            readClockProvider.overrideWithValue(ReadClock(now: () => now)),
            // This group fails the probe and keeps the list: the live poll would
            // read the list again past the failure.
            nzbgetPollingProvider.overrideWith((ref) {}),
            // A queue that came through the provider that notes it, or one
            // handed in whole, which nothing recorded.
            if (recorded)
              nzbgetClientProvider.overrideWithValue(_ListingNzbget(queue))
            else
              nzbgetQueueProvider.overrideWith((ref) async => queue),
            serviceSummaryProvider.overrideWith((ref, service) async {
              final down = ref.watch(probeDown);
              return ServiceSummary(
                service: service,
                status: down
                    ? ServiceSummaryStatus.offline
                    : ServiceSummaryStatus.online,
                host: 'nzbget.local:6789',
                version: down ? null : '21.1',
              );
            }),
            serviceKpiProvider.overrideWith(
              (ref, service) async => const <ServiceKpi>[],
            ),
            nzbgetStatusProvider.overrideWith((ref) async => _status),
            nzbgetHistoryProvider.overrideWith(
              (ref) async => const <NzbgetHistoryItem>[],
            ),
          ],
          child: const MaterialApp(home: NzbgetScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(NzbgetScreen)),
      );
    }

    testWidgets('says how old it is where the figures stopped counting', (
      tester,
    ) async {
      final container = await pumpScreen(tester, recorded: true);

      // Healthy: the row counts down, says nothing of its age, and the page
      // has no clock running.
      expect(find.textContaining(counting), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      expect(container.exists(minuteNowProvider), isFalse);
      expect(
        container.read(readClockProvider).at(key),
        readAt,
        reason: 'the queue was noted when it came back',
      );

      // The probe fails with the queue retained: the band goes up and the row
      // trades its countdown for the age of what it last read.
      now = readAt.add(const Duration(minutes: 6));
      container.read(probeDown.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.text('Job.1'), findsOneWidget);
      expect(find.textContaining(counting), findsNothing);
      expect(
        find.text('Downloading\u00A0· tv\u00A0· as of 6\u00A0min ago'),
        findsOneWidget,
      );

      // And the age moves with the minutes.
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(
        find.text('Downloading\u00A0· tv\u00A0· as of 7\u00A0min ago'),
        findsOneWidget,
      );

      // Back: the countdown returns, the age goes, and so does the clock.
      container.read(probeDown.notifier).state = false;
      await tester.pumpAndSettle();
      expect(find.byType(FaultBand), findsNothing);
      expect(find.textContaining(counting), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
      // The disposal the dropped watch scheduled runs a frame later.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.exists(minuteNowProvider), isFalse);
    });

    testWidgets('says nothing of the age of a read nobody recorded', (
      tester,
    ) async {
      final container = await pumpScreen(tester, recorded: false);
      container.read(probeDown.notifier).state = true;
      await tester.pumpAndSettle();

      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.textContaining(counting), findsOneWidget);
      expect(find.textContaining('as of'), findsNothing);
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
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith('Actions for '),
        ),
      );
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

  group('the add dialog', () {
    // Its field's controller was disposed the moment `showDialog` returned,
    // which is when the exit animation starts with the field still on screen:
    // the dialog threw "A TextEditingController was used after being disposed"
    // on its way out, whichever way it was closed.
    Future<_AppendingNzbget> openAdd(WidgetTester tester) async {
      final client = _AppendingNzbget();
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            nzbgetClientProvider.overrideWith((ref) => client),
            nzbgetStatusProvider.overrideWith((ref) async => _status),
          ],
          child: const MaterialApp(home: NzbgetScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add NZB'));
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets('closes on Add, sends the URL and lets its field go', (
      tester,
    ) async {
      final fields = _trackTextControllers();
      final client = await openAdd(tester);
      expect(fields.created, hasLength(1));

      await tester.enterText(
        find.byType(TextField),
        ' https://indexer.example.com/get/42.nzb ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add NZB by URL'), findsNothing);
      expect(client.appended, [
        (name: '42.nzb', url: 'https://indexer.example.com/get/42.nzb'),
      ]);
      expect(find.text('NZB added'), findsOneWidget);
      expect(fields.disposed, unorderedEquals(fields.created));
    });

    testWidgets('closes on Cancel, sends nothing and lets its field go', (
      tester,
    ) async {
      final fields = _trackTextControllers();
      final client = await openAdd(tester);

      await tester.enterText(find.byType(TextField), 'https://example.com/a');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add NZB by URL'), findsNothing);
      expect(client.appended, isEmpty);
      expect(fields.disposed, unorderedEquals(fields.created));
    });
  });
}

/// Records what an add asked NZBGet to fetch.
class _AppendingNzbget implements NzbgetClient {
  final appended = <({String name, String url})>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #append) {
      appended.add((
        name: invocation.positionalArguments[0] as String,
        url: invocation.positionalArguments[1] as String,
      ));
      // A real NZBID: anything above 0 is NZBGet taking the job.
      return Future<int>.value(42);
    }
    return super.noSuchMethod(invocation);
  }
}

/// The text controllers created and disposed from here to the end of the
/// test, as the framework reports them in debug builds.
({List<Object> created, List<Object> disposed}) _trackTextControllers() {
  final created = <Object>[];
  final disposed = <Object>[];
  void record(ObjectEvent event) {
    if (event.object is! TextEditingController) return;
    if (event is ObjectCreated) created.add(event.object);
    if (event is ObjectDisposed) disposed.add(event.object);
  }

  FlutterMemoryAllocations.instance.addListener(record);
  addTearDown(() => FlutterMemoryAllocations.instance.removeListener(record));
  return (created: created, disposed: disposed);
}

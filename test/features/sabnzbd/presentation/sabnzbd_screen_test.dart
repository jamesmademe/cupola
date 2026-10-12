import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  sabnzbdUrl: 'http://sab.local:8080',
  sabnzbdApiKey: 'key',
);

SabnzbdQueue _queue({
  bool paused = false,
  List<SabnzbdQueueSlot> slots = const [],
  int? reportedSlots,
}) => SabnzbdQueue(
  paused: paused,
  status: paused ? 'Paused' : 'Downloading',
  kbPerSec: 2048,
  mbLeft: 1500,
  mb: 3000,
  timeLeft: '0:12:30',
  slots: slots,
  reportedSlots: reportedSlots,
);

SabnzbdQueueSlot _slot({
  double mbLeft = 1024,
  double? mb,
  String id = '1',
  String filename = 'Dune.Part.Two.2024.2160p',
}) => SabnzbdQueueSlot(
  nzoId: 'SABnzbd_nzo_$id',
  filename: filename,
  status: 'Downloading',
  percentage: 50,
  category: 'movies',
  timeLeft: '0:12:30',
  mbLeft: mbLeft,
  mb: mb,
);

/// Records the `limit` every queue request asked for.
class _RecordingSabnzbd implements SabnzbdClient {
  final limits = <int>[];

  @override
  Future<SabnzbdQueue> getQueue({int limit = 50}) async {
    limits.add(limit);
    return _queue();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what a job delete asked SABnzbd to do.
class _DeletingSabnzbd implements SabnzbdClient {
  final deletes = <({String id, bool deleteFiles})>[];

  @override
  Future<void> deleteJob(String nzoId, {bool deleteFiles = false}) async {
    deletes.add((id: nzoId, deleteFiles: deleteFiles));
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

/// Finds the queue toggle by its label.
///
/// `find.widgetWithText(FilledButton, …)` cannot see it: `FilledButton.tonalIcon`
/// builds a private subclass, and `find.byType` matches the exact runtime type.
Finder _buttonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

/// The dashboard's ambient dependencies, stubbed so the screen under test is
/// the only thing doing any work.
List<Override> _ambient() => [
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'sab.local:8080',
      version: '4.2.0',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  sabnzbdHistoryProvider.overrideWith(
    (ref) async => const <SabnzbdHistorySlot>[],
  ),
];

void main() {
  testWidgets('an unconfigured SABnzbd renders the shared placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );

    // The private copy this replaced was one of four near-identical cards; the
    // shared widget is the state's single home.
    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
  });

  testWidgets('the pause toggle is inert until the queue state is known', (
    tester,
  ) async {
    // Regression: `queueAsync.asData?.value.paused ?? false` meant an
    // already-paused queue rendered "Pause all" for the whole first load, and a
    // tap in that window sent pause() to a queue that was already paused.
    final gate = Completer<SabnzbdQueue>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) => gate.future),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pump();

    final toggle = _buttonWithText('Pause all');
    expect(toggle, findsOneWidget);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);

    // Once the queue answers, the toggle tells the truth and becomes live.
    gate.complete(_queue(paused: true));
    await tester.pumpAndSettle();

    final resume = _buttonWithText('Resume all');
    expect(resume, findsOneWidget);
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
  });

  testWidgets('the add-NZB dialog shows categories the moment they arrive', (
    tester,
  ) async {
    // Regression: the dialog did `ref.read(sabnzbdCategoriesProvider)
    // .asData?.value` on a provider nothing else watches, so on first open it
    // was cold: the read returned AsyncLoading with no value, the dropdown was
    // hidden entirely, and the NZB was submitted with no category. The captured
    // local was never re-read either, so the dropdown stayed hidden even when
    // the fetch landed while the dialog was still open.
    final gate = Completer<List<String>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
          sabnzbdCategoriesProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add NZB'));
    await tester.pumpAndSettle();

    // Cold on open: the dialog says so rather than silently dropping the field.
    expect(find.text('Loading categories…'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    // The fetch lands while the dialog is still open, and the dialog notices.
    gate.complete(const ['*', 'movies', 'tv']);
    await tester.pumpAndSettle();

    expect(find.text('Loading categories…'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('a category-less SABnzbd shows no dropdown at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add NZB'));
    await tester.pumpAndSettle();

    expect(find.text('Add NZB by URL'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Loading categories…'), findsNothing);
  });

  testWidgets('a queue row states how big the job is, not only what is left', (
    tester,
  ) async {
    // The gap this row carried: `1.0 GB` on its own reads identically on a
    // download a third of the way in and on one about to finish, and it did
    // not even say it was a remainder. `mode=queue` returns `mb` on every slot
    // beside `mbleft`, so the second figure was a parse away.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith(
            (ref) async => _queue(slots: [_slot(mbLeft: 1024, mb: 4096)]),
          ),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Downloading · 12\u00A0min · 1.0\u00A0GB left of 4.0\u00A0GB'),
      findsOneWidget,
    );
  });

  testWidgets('a slot with no total drops the clause instead of faking it', (
    tester,
  ) async {
    // Never `of 0 B`, never a dash mid-sentence. A server that did not answer
    // leaves the row saying exactly what it does know.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith(
            (ref) async => _queue(slots: [_slot(mbLeft: 1024)]),
          ),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Downloading · 12\u00A0min · 1.0\u00A0GB left'),
      findsOneWidget,
    );
    expect(find.textContaining('of 0\u00A0B'), findsNothing);
    expect(find.textContaining('—'), findsNothing);
  });

  // OPS-02. The Queue tab drew `take(5)` slots with no count and no way to
  // reach the rest, over a provider that itself asked for a 50-slot page.
  group('the Queue tab is the whole queue', () {
    test('the queue provider asks SABnzbd for every job, not a page', () async {
      final client = _RecordingSabnzbd();
      final container = ProviderContainer(
        overrides: [sabnzbdClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await container.read(sabnzbdQueueProvider.future);

      // SABnzbd's `queue_info` admits every job when `limit` is zero.
      expect(client.limits, [SabnzbdClient.wholeQueue]);
      expect(SabnzbdClient.wholeQueue, 0);
    });

    test('the header count reads the server, and never passes off a page', () {
      expect(sabnzbdQueueCountLabel(null), isNull);
      expect(sabnzbdQueueCountLabel(_queue()), '0 jobs');
      expect(sabnzbdQueueCountLabel(_queue(slots: [_slot()])), '1 job');
      expect(
        sabnzbdQueueCountLabel(
          _queue(
            slots: [
              _slot(),
              _slot(id: '2'),
            ],
            reportedSlots: 2,
          ),
        ),
        '2 jobs',
      );
      // A server that sent fewer slots than it counted is drawn as what it is.
      expect(
        sabnzbdQueueCountLabel(_queue(slots: [_slot()], reportedSlots: 12)),
        '1 of 12 jobs shown',
      );
    });

    testWidgets('every job is a reachable row, and the header counts them', (
      tester,
    ) async {
      final slots = [
        for (var i = 1; i <= 8; i++) _slot(id: '$i', filename: 'Job.$i'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            sabnzbdQueueProvider.overrideWith(
              (ref) async => _queue(slots: slots, reportedSlots: 8),
            ),
            sabnzbdCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
          ],
          child: const MaterialApp(home: SabnzbdScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(_queueSubtitle(tester), '8 jobs');
      final list = find.byType(Scrollable).first;
      // The sixth to eighth jobs are the rows the old cap cut off.
      for (final name in ['Job.6', 'Job.7', 'Job.8']) {
        await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('a queue still loading states no count, never zero', (
      tester,
    ) async {
      final gate = Completer<SabnzbdQueue>();
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            sabnzbdQueueProvider.overrideWith((ref) => gate.future),
            sabnzbdCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
          ],
          child: const MaterialApp(home: SabnzbdScreen()),
        ),
      );
      await tester.pump();

      expect(_queueSubtitle(tester), isNull);
      expect(find.textContaining('0 jobs'), findsNothing);

      gate.complete(_queue());
      await tester.pumpAndSettle();
      expect(_queueSubtitle(tester), '0 jobs');
    });

    testWidgets('the capped history block is gone from the Queue tab', (
      tester,
    ) async {
      // It was a ten-row copy of the History tab, capped without saying so.
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
            sabnzbdCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
          ],
          child: const MaterialApp(home: SabnzbdScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is SectionHeader && w.title == 'History',
        ),
        findsNothing,
      );
    });
  });

  group('deleting a job', () {
    Future<_DeletingSabnzbd> pumpAndOpen(WidgetTester tester) async {
      final client = _DeletingSabnzbd();
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            sabnzbdClientProvider.overrideWith((ref) => client),
            sabnzbdQueueProvider.overrideWith(
              (ref) async => _queue(slots: [_slot()]),
            ),
            sabnzbdCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
          ],
          child: const MaterialApp(home: SabnzbdScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Job actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete job'));
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets('asks first, and Cancel sends nothing', (tester) async {
      // It fired on the menu tap, one row below Pause, and "Job removed" was
      // the only word about it.
      final client = await pumpAndOpen(tester);

      expect(find.text('Delete this job?'), findsOneWidget);
      expect(
        find.textContaining(
          'Dune.Part.Two.2024.2160p leaves the SABnzbd queue',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(client.deletes, isEmpty);
      expect(find.text('Job removed'), findsNothing);
    });

    testWidgets('keeps the downloaded files unless asked to delete them', (
      tester,
    ) async {
      final client = await pumpAndOpen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete job'));
      await tester.pumpAndSettle();

      expect(client.deletes, [(id: 'SABnzbd_nzo_1', deleteFiles: false)]);
      expect(find.text('Job removed'), findsOneWidget);
    });

    testWidgets('the files go only when the box is ticked', (tester) async {
      final client = await pumpAndOpen(tester);
      await tester.tap(find.text('Also delete downloaded files'));
      await tester.pumpAndSettle();
      // Ticking the box rewrites the verb, so the button says what goes.
      expect(find.widgetWithText(FilledButton, 'Delete job'), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete job and files'),
      );
      await tester.pumpAndSettle();

      expect(client.deletes, [(id: 'SABnzbd_nzo_1', deleteFiles: true)]);
      expect(find.text('Job and its files deleted'), findsOneWidget);
    });
  });

  testWidgets(
    'the add dialog closes on Add, sends the URL and lets its field go',
    (tester) async {
      // The dialog owns its field's controller, so it lives exactly as long
      // as the field: disposing it when `showDialog` returns is what made
      // the NZBGet and Transmission dialogs fail on their way out.
      final created = <Object>[];
      final disposed = <Object>[];
      void record(ObjectEvent event) {
        if (event.object is! TextEditingController) return;
        if (event is ObjectCreated) created.add(event.object);
        if (event is ObjectDisposed) disposed.add(event.object);
      }

      FlutterMemoryAllocations.instance.addListener(record);
      addTearDown(
        () => FlutterMemoryAllocations.instance.removeListener(record),
      );
      final client = _AddingSabnzbd();
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            ..._ambient(),
            sabnzbdClientProvider.overrideWith((ref) => client),
            sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
            sabnzbdCategoriesProvider.overrideWith(
              (ref) async => const <String>[],
            ),
          ],
          child: const MaterialApp(home: SabnzbdScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add NZB'));
      await tester.pumpAndSettle();
      expect(created, hasLength(1));

      await tester.enterText(
        find.byType(TextField),
        'https://indexer.example.com/get/42.nzb',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add NZB by URL'), findsNothing);
      expect(client.added, ['https://indexer.example.com/get/42.nzb']);
      expect(find.text('NZB added'), findsOneWidget);
      expect(disposed, unorderedEquals(created));
    },
  );
}

/// Records the URLs an add handed SABnzbd.
class _AddingSabnzbd implements SabnzbdClient {
  final added = <String>[];

  @override
  Future<void> addUrl(
    String nzbUrl, {
    String? category,
    int priority = 0,
  }) async {
    added.add(nzbUrl);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  final now = DateTime.now();
  DateTime today(int hour) => DateTime(now.year, now.month, now.day, hour);

  /// A moment that is always today and always in the past, whatever hour the
  /// suite runs at.
  ///
  /// The screen reads the real clock — `sabnzbdOverviewHistoryProvider` calls
  /// `DateTime.now()` — so a row placed a flat hour before `now` lands on
  /// *yesterday* between 00:00 and 00:59, gets dropped by the window rule, and
  /// turns this file red for one hour out of every twenty-four on whoever's
  /// machine happens to run it then. Pinned to the start of the day instead
  /// whenever an hour ago would fall out of it.
  DateTime earlierToday() {
    final anHourAgo = now.subtract(const Duration(hours: 1));
    return anHourAgo.isBefore(today(0)) ? today(0) : anHourAgo;
  }

  testWidgets('draws the regions in the order the board stacks them', (
    tester,
  ) async {
    await _pump(tester);

    // Overview alone carries the identity block and the readouts.
    expect(find.byType(ServiceOverviewIdentity), findsOneWidget);
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // Queue above History, which is the board's order on both artboards and
    // the spine's: the service's own work first, history last.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Queue', 'History'],
    );
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      ['opens the SABnzbd Queue tab', 'opens the SABnzbd History tab'],
    );
  });

  testWidgets('the headers state the counts the sections were cut from', (
    tester,
  ) async {
    await _pump(
      tester,
      history: [
        for (var i = 0; i < 6; i++)
          _history(
            name: 'done $i',
            completed: today(9).add(Duration(minutes: i)),
          ),
        _history(name: 'broken', status: 'Failed', completed: today(10)),
      ],
      queue: _queue(
        mbLeft: 1024,
        slots: [
          _slot(filename: 'a'),
          _slot(filename: 'b'),
        ],
      ),
    );

    expect(find.text('today · 6 completed · 1 failed'), findsOneWidget);
    expect(find.text('2 jobs · 1.0 GB'), findsOneWidget);
  });

  testWidgets('a header over a cut page states a floor, not a day', (
    tester,
  ) async {
    // Every record today and the page came back full: what fell off the end is
    // unknown, so the counts are at-least figures and the header says so. A
    // bare `100 completed` there would be the size of the request wearing the
    // name of the day.
    await _pump(
      tester,
      history: [
        for (var i = 0; i < sabnzbdHistoryPageSize; i++)
          _history(
            name: 'done $i',
            completed: today(9).add(Duration(minutes: i)),
          ),
      ],
    );

    expect(
      find.text('today · $sabnzbdHistoryPageSize+ completed'),
      findsOneWidget,
    );
  });

  testWidgets('a history that did not answer says so in a word', (
    tester,
  ) async {
    // The header is spoken as "History, <subtitle>", and an em dash there is
    // heard as nothing at all — the one place on this page where a listener
    // gets less than a viewer, who at least sees the error state below it.
    await _pump(tester, historyFails: true);

    final subtitles = tester
        .widgetList<SectionHeader>(find.byType(SectionHeader))
        .map((header) => header.subtitle);
    expect(subtitles.last, 'not answering');
    // The em dash still belongs to the readout band, where `ServiceKpi`
    // speaks it as "unavailable" — never to a header a reader hears as a title
    // and a piece of punctuation.
    expect(subtitles, isNot(contains('—')));
  });

  testWidgets(
    'a paused queue says so in words, and is not painted as a fault',
    (tester) async {
      await _pump(
        tester,
        queue: _queue(
          paused: true,
          mbLeft: 1024,
          slots: [_slot(status: 'Paused')],
        ),
      );

      // Stated, because pausing is the user's own decision — the one fact the
      // readout band cannot show now that Speed reads a legitimate 0 B/s.
      expect(find.text('1 job · 1.0 GB · paused'), findsOneWidget);
    },
  );

  testWidgets('the ETA of a paused queue is an em dash, never a zero', (
    tester,
  ) async {
    await _pump(
      tester,
      // SABnzbd keeps reporting the estimate it last had; the queue is not
      // moving, so there is no estimate behind it.
      queue: _queue(paused: true, timeLeft: '0:07:00', slots: [_slot()]),
    );

    expect(
      find.semantics.byLabel('ETA: unavailable, queue paused'),
      findsOneWidget,
    );
    expect(find.text('0 min'), findsNothing);
    expect(find.text('7 min'), findsNothing);
  });

  testWidgets('a failed history row is one sentence, not four fragments', (
    tester,
  ) async {
    await _pump(
      tester,
      history: [
        _history(
          name: 'Killers.of.the.Flower.Moon.2023.2160p',
          status: 'Failed',
          failMessage: 'missing 14 articles',
          category: 'movies',
          completed: earlierToday(),
        ),
      ],
    );

    // The relative phrase is whatever the real clock makes of `earlierToday()`
    // — "1 h ago" most of the day, minutes just after midnight — so the
    // assertion pins the sentence and leaves that one part open rather than
    // pinning an hour the suite cannot control.
    expect(
      find.semantics.byLabel(
        RegExp(
          r'^Killers\.of\.the\.Flower\.Moon\.2023\.2160p, failed, '
          r'missing 14 articles, .+, movies$',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a queue row speaks its progress before its detail', (
    tester,
  ) async {
    await _pump(
      tester,
      queue: _queue(
        slots: [
          _slot(
            filename: 'Dune.Part.Two.2024.2160p',
            status: 'Downloading',
            percentage: 72,
            mbLeft: 1024,
            mb: 4096,
            timeLeft: '0:02:00',
            category: 'movies',
          ),
        ],
      ),
    );

    // One sentence, and the size clause carries both halves of the fact: what
    // is left, and of how much. The remainder on its own reads the same at 30%
    // as at 95%, which is exactly what a listener cannot see the bar for.
    expect(
      find.semantics.byLabel(
        'Dune.Part.Two.2024.2160p, 72% downloaded, '
        'downloading, 1.0 GB left of 4.0 GB, 2 min, movies',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(
      tester,
      historyFails: true,
      queue: _queue(slots: [_slot(filename: 'still here')]),
    );

    // The failed region says so in its own slot…
    expect(find.byType(AppErrorState), findsOneWidget);
    // …and the other one still drew.
    expect(find.byType(SectionHeader), findsNWidgets(2));
    expect(find.text('still here'), findsOneWidget);
  });

  testWidgets(
    'an empty day and an empty queue are resting states, not errors',
    (tester) async {
      await _pump(tester);

      expect(find.text('Nothing finished today'), findsOneWidget);
      expect(find.text('Nothing in the queue'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    },
  );

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      queue: _queue(
        mbLeft: 1024,
        slots: [
          _slot(
            filename:
                'A.Very.Long.Release.Name.2024.2160p.UHD.BluRay.x265-GROUP',
            percentage: 100,
            category: 'movies',
          ),
        ],
      ),
      history: [
        _history(
          name: 'Another.Very.Long.Release.Name.2024.2160p.WEB-DL-GROUP',
          status: 'Failed',
          failMessage: 'missing 14 articles out of 320',
          completed: today(9),
        ),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a SABnzbd that was never set up gets its own door', (
    tester,
  ) async {
    var queueReads = 0;
    var historyReads = 0;
    await _pump(
      tester,
      configured: false,
      onQueueRead: () => queueReads++,
      onHistoryRead: () => historyReads++,
    );

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    // `.forService`, so the button deep-links to SABnzbd's own connection form
    // rather than to the settings index.
    expect(placeholder.service, ServiceKey.sabnzbd);
    expect(find.byType(SectionHeader), findsNothing);
    // And nothing reached a provider: `sabnzbdClientProvider` throws when the
    // service is not configured, and a FutureProvider that throws is a *failed*
    // provider — Riverpod then schedules a backoff retry for a condition no
    // waiting changes, which surfaces here as a pending timer.
    expect(queueReads, 0);
    expect(historyReads, 0);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  SabnzbdQueue? queue,
  List<SabnzbdHistorySlot> history = const [],
  bool historyFails = false,
  bool configured = true,
  double textScaleFactor = 1.0,
  VoidCallback? onQueueRead,
  VoidCallback? onHistoryRead,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch the deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: _overrides(
        queue: queue ?? _queue(),
        history: history,
        historyFails: historyFails,
        configured: configured,
        onQueueRead: onQueueRead,
        onHistoryRead: onHistoryRead,
      ),
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const SabnzbdOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _overrides({
  required SabnzbdQueue queue,
  required List<SabnzbdHistorySlot> history,
  required bool historyFails,
  required bool configured,
  VoidCallback? onQueueRead,
  VoidCallback? onHistoryRead,
}) => [
  currentSettingsProvider.overrideWith(
    (ref) => configured
        ? settingsWith(
            sabnzbdUrl: 'http://sab.local:8080',
            sabnzbdApiKey: 'key',
          )
        : const SettingsModel(),
  ),
  // The reachability probe, answered. The identity block is the shared widget's
  // business; what matters here is that it has something to say.
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'sab.local:8080',
      version: '4.4.1',
    ),
  ),
  sabnzbdQueueProvider.overrideWith((ref) async {
    onQueueRead?.call();
    return queue;
  }),
  // The Overview asks for its own history page — a hundred records, not the
  // twenty `sabnzbdHistoryProvider` takes — because it counts a day.
  sabnzbdOverviewHistoryPageProvider.overrideWith((ref) async {
    onHistoryRead?.call();
    if (historyFails) throw Exception('history failed');
    return history;
  }),
];

// ─── Builders ───────────────────────────────────────────────────────────────

SabnzbdQueue _queue({
  bool paused = false,
  double kbPerSec = 0,
  double mbLeft = 0,
  String timeLeft = '0:00:00',
  List<SabnzbdQueueSlot> slots = const [],
}) => SabnzbdQueue(
  paused: paused,
  status: paused ? 'Paused' : 'Downloading',
  kbPerSec: kbPerSec,
  mbLeft: mbLeft,
  mb: mbLeft,
  timeLeft: timeLeft,
  slots: slots,
);

SabnzbdQueueSlot _slot({
  String filename = 'Release',
  String status = 'Downloading',
  int percentage = 50,
  double mbLeft = 100,
  double? mb,
  String timeLeft = '0:05:00',
  String category = '',
}) => SabnzbdQueueSlot(
  nzoId: 'SABnzbd_nzo_$filename',
  filename: filename,
  status: status,
  percentage: percentage,
  category: category,
  timeLeft: timeLeft,
  mbLeft: mbLeft,
  mb: mb,
);

SabnzbdHistorySlot _history({
  String name = 'Release',
  String status = 'Completed',
  String category = '',
  int bytes = 0,
  String? failMessage,
  required DateTime? completed,
}) => SabnzbdHistorySlot(
  nzoId: 'SABnzbd_nzo_$name',
  name: name,
  status: status,
  category: category,
  bytes: bytes,
  completed: completed,
  failMessage: failMessage,
);

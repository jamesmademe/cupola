import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('puts what needs a decision before what is merely outstanding', (
    tester,
  ) async {
    // Deliberately NOT the board's order: both NZBGet artboards stack Queue
    // above History. The screen's own doc comment argues the deviation; this
    // asserts it, so restoring the board's order is a decision someone makes
    // rather than a red test whose name says they are wrong.

    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // History first: a failed download is the only thing here that needs a
    // person, and a queue at 56% needs nobody.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['History', 'Queue'],
    );
    // Absent rather than stubbed — the client has no `config`, no `listfeeds`
    // and no `log`.
    expect(find.text('Servers'), findsNothing);
    expect(find.text('Feeds'), findsNothing);
    expect(find.text('Messages'), findsNothing);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      ['opens the NZBGet History tab', 'opens the NZBGet Queue tab'],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel('NZBGet, nzbget.local:6789, v21.1, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable NZBGet reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, online: false);

      expect(
        find.semantics.byLabel('NZBGet, nzbget.local:6789, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a queue row is spoken as one sentence', (tester) async {
    await _pump(
      tester,
      queue: [
        _group(
          name: 'Silo.S03E01.2160p.WEB-DL',
          status: 'DOWNLOADING',
          fileSizeMb: 4915,
          remainingSizeMb: 2162,
        ),
      ],
    );

    expect(
      find.semantics.byLabel(
        'Silo.S03E01.2160p.WEB-DL, tv, downloading, 4.8\u00A0GB, 56 percent',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed history row is spoken as one sentence, and leads', (
    tester,
  ) async {
    await _pump(
      tester,
      history: [
        _item(name: 'Andor.S02E02', at: _todayAt(0.25)),
        _item(name: 'Sugar.S02E01', at: _todayAt(0.5), status: 'FAILURE/PAR'),
      ],
    );

    expect(
      find.semantics.byLabel(
        // The age clause is whatever the clock makes it; the sentence around
        // it is the assertion, and the window itself is pinned to a fixed
        // `now` in the provider test.
        RegExp(r'^Sugar\.S02E01, failed, par repair, tv, .+$'),
      ),
      findsOneWidget,
    );
    // The header states the day's totals, whatever the preview shows.
    expect(_subtitleOf(tester, 'History'), 'today · 1 completed · 1 failed');
  });

  testWidgets('a status that did not answer costs the ETA, not the queue', (
    tester,
  ) async {
    await _pump(
      tester,
      queue: [_group(name: 'Silo', status: 'DOWNLOADING')],
      failStatus: true,
    );

    // The rows are still there…
    expect(find.text('Silo'), findsOneWidget);
    // …and the header states only what was measured: no "0 B left", no ETA
    // computed from a rate nobody reported.
    expect(_subtitleOf(tester, 'Queue'), '1 downloading');
  });

  testWidgets('a history that did not answer reads — and never 0 completed', (
    tester,
  ) async {
    await _pump(tester, failHistory: true);

    expect(_subtitleOf(tester, 'History'), 'today · —');
    // The failed region says so in its own slot…
    expect(find.byType(AppErrorState), findsOneWidget);
    // …and the other one still drew its heading.
    expect(find.byType(SectionHeader), findsNWidgets(2));
  });

  testWidgets('an idle queue prints a sentence, never a blank line', (
    tester,
  ) async {
    // The commonest resting state of a download client. Every clause of the
    // Queue subtitle is guarded off at once here, and an empty string is not a
    // shorter header: `SectionHeader` treats a non-null subtitle as a subtitle
    // and would draw a blank line under the word Queue, then speak "Queue, "
    // with a dangling comma.
    await _pump(
      tester,
      status: const NzbgetStatus(
        downloadRateBytes: 0,
        remainingSizeMb: 0,
        paused: false,
      ),
    );

    expect(_subtitleOf(tester, 'Queue'), 'nothing queued');
    expect(find.text('Nothing in the queue'), findsOneWidget);
  });

  testWidgets('a refresh does not print — over the rows it is still drawing', (
    tester,
  ) async {
    // `AsyncValueWidget` keeps the last readout at full ink under the fault
    // band, so the header above it must read the retained value too. With
    // `asData?.value` this says "today · —" over a row stating the very figure
    // it claims not to know — on every pull-to-refresh, and for as long as the
    // box stays off the network.
    await _pump(
      tester,
      history: [_item(name: 'Andor.S02E02', at: _todayAt(0.5))],
      historyFailsOnRefetch: true,
    );

    expect(_subtitleOf(tester, 'History'), 'today · 1 completed');

    ProviderScope.containerOf(
      tester.element(find.byType(NzbgetOverviewScreen)),
    ).invalidate(nzbgetHistoryProvider);
    await tester.pumpAndSettle();

    // The row survived the failed refetch…
    expect(find.text('Andor.S02E02 · success'), findsOneWidget);
    // …so the header must not disown it.
    expect(_subtitleOf(tester, 'History'), 'today · 1 completed');
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      queue: [
        _group(
          name: 'A.Release.Name.That.Goes.On.And.On.2160p.WEB-DL.DDP5.1-GROUP',
          status: 'REPAIRING',
        ),
      ],
      history: [
        _item(name: 'Another.Very.Long.Release.Name.1080p', at: _todayAt(0.5)),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an NZBGet that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.nzbget);
    // Nothing reached a provider: `nzbgetClientProvider` throws when NZBGet is
    // not configured, and a `FutureProvider` that throws schedules a retry for
    // a condition no waiting changes.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

/// The subtitle [SectionHeader] with [title] is printing.
String? _subtitleOf(WidgetTester tester, String title) => tester
    .widgetList<SectionHeader>(find.byType(SectionHeader))
    .firstWhere((header) => header.title == title)
    .subtitle;

Future<void> _pump(
  WidgetTester tester, {
  List<NzbgetGroup> queue = const [],
  List<NzbgetHistoryItem> history = const [],
  bool failStatus = false,
  bool failHistory = false,
  bool historyFailsOnRefetch = false,
  NzbgetStatus status = const NzbgetStatus(
    downloadRateBytes: 3100000,
    remainingSizeMb: 2150,
    paused: false,
  ),
  bool online = true,
  bool configured = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  var historyCalls = 0;

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(nzbgetUrl: 'http://nzbget.local:6789')
              : const SettingsModel(),
        ),
        // NZBGet's reachability probe builds its own `NzbgetClient` rather than
        // going through `serviceStatusClientFactoryProvider`, so the summary is
        // overridden directly — the alternative is a real socket in a unit
        // test.
        serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: online
                ? ServiceSummaryStatus.online
                : ServiceSummaryStatus.offline,
            host: 'nzbget.local:6789',
            version: online ? '21.1' : null,
          ),
        ),
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
        nzbgetStatusProvider.overrideWith((ref) async {
          if (failStatus) throw Exception('status failed');
          return status;
        }),
        nzbgetQueueProvider.overrideWith((ref) async => queue),
        nzbgetHistoryProvider.overrideWith((ref) async {
          if (failHistory) throw Exception('history failed');
          // Answers once, then refuses — the shape of a box that drops off the
          // network between the first load and a pull-to-refresh.
          if (historyFailsOnRefetch && historyCalls++ > 0) {
            throw Exception('history failed');
          }
          return history;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const NzbgetOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

NzbgetGroup _group({
  required String name,
  required String status,
  String category = 'tv',
  int fileSizeMb = 4915,
  int remainingSizeMb = 2162,
}) => NzbgetGroup(
  nzbId: name.hashCode,
  name: name,
  status: status,
  category: category,
  fileSizeMb: fileSizeMb,
  remainingSizeMb: remainingSizeMb,
);

/// A moment [fraction] of the way from local midnight to now.
///
/// Fixtures cannot be `now - 3 h`: the screen windows history to the local
/// calendar day, and a suite running at 02:00 would put that record
/// *yesterday* and empty the section. Anchoring to the elapsed part of today
/// is in the window at every hour the suite could run. The boundary itself is
/// tested against a fixed `now` in the provider test, where it belongs.
DateTime _todayAt(double fraction) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final elapsed = now.difference(midnight);
  return midnight.add(
    Duration(microseconds: (elapsed.inMicroseconds * fraction).round()),
  );
}

NzbgetHistoryItem _item({
  required String name,
  required DateTime at,
  String status = 'SUCCESS/ALL',
  String category = 'tv',
}) => NzbgetHistoryItem(
  id: name.hashCode,
  name: name,
  status: status,
  category: category,
  time: at,
);

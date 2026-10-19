import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the stacks and no Needs attention: Dockge reports no '
      'fault', (tester) async {
    await _pump(
      tester,
      stacks: [
        _stack('media'),
        _stack('bazarr', status: DockgeStackStatus.exited),
      ],
    );

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // A stopped stack may have been brought down on purpose, and the push
    // says nothing more: a region for faults would hold none. Agents is
    // absent because this Dockge has one instance.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Stacks'],
    );
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('nothing the protocol cannot answer is drawn', (tester) async {
    await _pump(tester);

    // No update check exists in Socket.IO's vocabulary, so neither the readout
    // nor the button the board draws for it can be honest.
    expect(find.textContaining('Update'), findsNothing);
    expect(find.textContaining('newer'), findsNothing);
    // No container census either: `serviceStatusList` is per stack, and a sum
    // over the five rows this preview draws is not a total.
    expect(find.textContaining('containers'), findsNothing);
    // And the terminal card has no stack to attach to at tab level, which is
    // the open design question rather than this page's to answer.
    expect(find.text('Terminal'), findsNothing);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      ['opens the Dockge Stacks tab'],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel('Dockge, dockge.lan:5001, v1.5.0, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable Dockge reads Did not answer, and its version is —',
    (tester) async {
      await _pump(tester, online: false);

      expect(
        find.semantics.byLabel('Dockge, dockge.lan:5001, —, Did not answer'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a stopped stack is backlog: one neutral row, never amber', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        _stack('media'),
        _stack('bazarr', status: DockgeStackStatus.exited),
      ],
    );

    final colorScheme = AppTheme.darkTheme().colorScheme;
    final neutral = statusToneColor(
      colorScheme,
      StatusTone.neutral,
      surface: colorScheme.surfaceContainerLow,
    );
    final amber = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surfaceContainerLow,
    );

    // Dockge does not say whether the stop was intended, so the row says that
    // and no more, and it is never a fault.
    final row = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(ServiceOverviewRow, '1 stack is stopped'),
    );
    expect(row.titleColor, neutral);
    expect(row.titleColor, isNot(amber));
    expect(find.textContaining('Dockge does not say why'), findsOneWidget);
    expect(find.textContaining('Exited'), findsNothing);
  });

  testWidgets('an inactive stack is backlog: counted, never painted amber', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        _stack('media'),
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('bazarr', status: DockgeStackStatus.exited),
      ],
    );

    final colorScheme = AppTheme.darkTheme().colorScheme;
    final amber = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surfaceContainerLow,
    );
    final neutral = statusToneColor(
      colorScheme,
      StatusTone.neutral,
      surface: colorScheme.surfaceContainerLow,
    );

    final backlog = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(ServiceOverviewRow, '1 stack is inactive'),
    );
    // The commonest way the five-arm rule breaks: a stack the user brought down
    // wearing the same colour as one that died. Nothing here is amber now.
    expect(backlog.titleColor, neutral);
    expect(backlog.titleColor, isNot(amber));

    final stopped = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(ServiceOverviewRow, '1 stack is stopped'),
    );
    expect(stopped.titleColor, neutral);
  });

  testWidgets('the stacks that are not running sit under the running ones, '
      'each group counting its own', (tester) async {
    await _pump(
      tester,
      stacks: [
        for (var i = 0; i < 6; i++)
          _stack('down-$i', status: DockgeStackStatus.exited),
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('media'),
      ],
    );

    // Each group states its own size, in words, and the stopped group counts
    // the whole six: nothing is capped out of sight.
    expect(find.text('6 stacks are stopped'), findsOneWidget);
    expect(find.text('1 stack is inactive'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('media')).dy,
      lessThan(tester.getTopLeft(find.text('6 stacks are stopped')).dy),
    );
  });

  testWidgets('the stacks header never sums the backlog into a figure', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        _stack('bazarr', status: DockgeStackStatus.exited),
        for (var i = 0; i < 8; i++)
          _stack('template-$i', status: DockgeStackStatus.createdFile),
      ],
    );

    // One stopped stack and eight templates nobody ever started. "9" here
    // would be the five-arm rule broken in the figure, over rows that got it
    // right: a tidy server reading as nine things on fire.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Stacks'),
    );
    expect(header.subtitle, isNull);
    // The backlog is not silenced by that: each state states its own size, in
    // words, in the neutral row that is about it, and a server whose stacks
    // are all down is not an empty one.
    expect(find.text('8 stacks are inactive'), findsOneWidget);
    expect(find.text('1 stack is stopped'), findsOneWidget);
    expect(find.byType(ServiceOverviewEmpty), findsNothing);
  });

  testWidgets('a push that never arrived reads `—` and never 0', (
    tester,
  ) async {
    await _pump(tester, failStacks: true);

    // A "0" over an unanswered question claims every stack is up, which is the
    // reading the user would act on. The stacks header therefore prints no
    // figure at all while the push is out.
    expect(find.text('0'), findsNothing);
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Stacks'),
    );
    expect(header.subtitle, isNull);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failStacks: true);

    // The stacks region says so in its own slot, under its heading, and the
    // identity and the readouts above it are still drawn.
    expect(find.byType(SectionHeader), findsOneWidget);
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so its stacks are not shown."),
      findsOneWidget,
    );
    expect(find.byType(ServiceKpiPeek), findsOneWidget);
  });

  testWidgets('a stack row is the way into its log and its controls', (
    tester,
  ) async {
    await _pump(tester, stacks: [_stack('immich')]);

    // The board's terminal card, made answerable: the row names the stack, and
    // the stack's own page carries the live combined terminal.
    expect(
      find.semantics.byHint('opens immich, with its log and controls'),
      findsOneWidget,
    );
    // And the row still speaks as one sentence rather than two fragments.
    expect(find.semantics.byLabel('immich, running'), findsOneWidget);
  });

  testWidgets('one Dockge instance draws no Agents section', (tester) async {
    await _pump(tester);

    // The same guard the app-bar lens keeps: a picker (or a list) offering
    // one choice teaches the user there is a decision to make when there is not.
    expect(find.text('Agents'), findsNothing);
  });

  testWidgets('two instances draw the section, and say which one answered', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [_stack('media'), _stack('immich')],
      agents: const [
        DockgeAgent.local,
        DockgeAgent(endpoint: 'nas.lan:5001', name: 'nas', status: 'offline'),
      ],
    );

    final agentsHeader = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Agents'),
    );
    expect(agentsHeader.subtitle, '2 instances\u00A0· 1 did not answer');
    // No link and no picker: the lens is an app-bar control, and a second one
    // here would be two controls fighting over one piece of state.
    expect(agentsHeader.onTap, isNull);

    // And the stack census names the instance it was counted on: the client
    // holds one agent's stacks at a time, so a bare "2 stacks" here would state
    // a subset as the deployment's total.
    final stacksHeader = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Stacks'),
    );
    expect(stacksHeader.subtitle, 'on local');
  });

  testWidgets('the stacks header adds to the readout rail, never repeats it', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        _stack('media'),
        _stack('immich'),
        _stack('archive', status: DockgeStackStatus.createdFile),
      ],
    );

    // `_dockgeKpis` fills the rail two regions above with Stacks / Running /
    // Stopped / Inactive off this same push. A subtitle spelling them again is
    // the same four figures twice in one screenful, wrapping to three lines
    // beside the "Stacks →" link, so on a single-instance Dockge with
    // nothing truncated the header has nothing to add and says nothing.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Stacks'),
    );
    expect(header.subtitle, isNull);
    expect(find.textContaining('3 stacks'), findsNothing);
  });

  testWidgets('the stacks header says how much the preview leaves out', (
    tester,
  ) async {
    await _pump(tester, stacks: [for (var i = 0; i < 7; i++) _stack('app-$i')]);

    // The one figure the rail cannot carry: this preview is capped at five, and
    // how many running stacks it did not draw exists nowhere else on the page.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Stacks'),
    );
    expect(header.subtitle, '5 of 7 running');
  });

  testWidgets('the agents header counts every instance, not a sample of them', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [_stack('media')],
      agents: const [
        DockgeAgent.local,
        DockgeAgent(endpoint: 'a:5001', name: 'a'),
        DockgeAgent(endpoint: 'b:5001', name: 'b'),
        DockgeAgent(endpoint: 'c:5001', name: 'c'),
        DockgeAgent(endpoint: 'd:5001', name: 'd'),
        DockgeAgent(endpoint: 'e:5001', name: 'e', status: 'offline'),
        DockgeAgent(endpoint: 'f:5001', name: 'f', status: 'offline'),
      ],
    );

    // Seven instances, two of them dead, and both dead ones sit past where a
    // five-row cap used to fall. This section has no "see the rest" tab, so a
    // capped list would have read "5 instances · 0 not answering" over a hub
    // with two agents down and mentioned neither of them anywhere.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Agents'),
    );
    expect(header.subtitle, '7 instances\u00A0· 2 did not answer');
    expect(find.text('f'), findsOneWidget);
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      stacks: [
        _stack(
          'a-compose-project-with-an-extremely-long-directory-name-2026',
          tags: ['media', 'production', 'behind-the-proxy'],
        ),
        _stack('bazarr', status: DockgeStackStatus.exited),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pull asks the server again when it did not answer', (
    tester,
  ) async {
    probeCalls = 0;
    await _pump(
      tester,
      stacks: [_stack('media')],
      probe: (call) async => call == 1
          ? ServiceSummary.failed(
              ServiceKey.dockge,
              host: 'dockge.lan:5001',
              error: DioException(
                requestOptions: RequestOptions(),
                type: DioExceptionType.connectionTimeout,
              ),
            )
          : const ServiceSummary(
              service: ServiceKey.dockge,
              status: ServiceSummaryStatus.online,
              host: 'dockge.lan:5001',
              version: '1.5.0',
            ),
    );

    // The one red line stands in for the sections.
    expect(find.byType(ServiceOverviewUnanswered), findsOneWidget);
    expect(find.text('Stacks'), findsNothing);

    // Through the indicator's own state: what is under test is the list the
    // callback invalidates, not the gesture.
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    // The pull reached the probe, not only the wrapper that reads its cache.
    expect(probeCalls, 2);
    expect(find.byType(ServiceOverviewUnanswered), findsNothing);
    expect(find.text('Stacks'), findsOneWidget);
  });

  testWidgets('a Dockge that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.dockge);
    // Nothing behind the door was built, which is the point: `dockgeClientProvider`
    // throws "not configured", and a provider that throws is a *failed* provider
    // retrying on a backoff for a condition no waiting changes. A pending timer
    // here would be the tell.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

int probeCalls = 0;

Future<void> _pump(
  WidgetTester tester, {
  List<DockgeStack> stacks = const [],
  List<DockgeAgent> agents = const [DockgeAgent.local],
  bool failStacks = false,
  bool online = true,
  bool configured = true,
  double textScaleFactor = 1.0,
  Future<ServiceSummary> Function(int call)? probe,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // **No `retry:` override here, deliberately.** Riverpod re-runs a build
      // that throws ten times on an exponential backoff, and this harness used
      // to switch that off at the scope so a deliberately failing section could
      // settle. It is the production providers' job: the four folds over the
      // two pushes carry `retry: noProviderRetry`, because re-reading an error
      // a stream is still holding cannot change the answer and only leaves a
      // pending timer behind. If one of them ever loses it, the failing-source
      // tests below stop settling, which is the point of taking this out.
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  dockgeUrl: 'http://dockge.lan:5001',
                  dockgeUsername: 'admin',
                  dockgePassword: 'secret',
                )
              : const SettingsModel(),
        ),
        // The one push both stack regions are folded from.
        dockgeStackListProvider.overrideWith(
          (ref) => failStacks
              ? Stream<List<DockgeStack>>.error(Exception('socket dropped'))
              : Stream.value(stacks),
        ),
        dockgeAgentsProvider.overrideWith((ref) => Stream.value(agents)),
        // With a [probe], the connection's own probe is what answers and the
        // lens wrapper keeps delegating to it, which is production's shape: a
        // pull that does not reach the probe is a pull that never asked.
        if (probe != null)
          instanceSummaryProvider.overrideWith(
            (ref, key) => probe(++probeCalls),
          )
        else
          serviceSummaryProvider.overrideWith(
            (ref, service) async => ServiceSummary(
              service: service,
              status: online
                  ? ServiceSummaryStatus.online
                  : ServiceSummaryStatus.offline,
              host: 'dockge.lan:5001',
              version: online ? '1.5.0' : null,
            ),
          ),
        // The readout rail is not what these tests are about, and it reads the
        // stack list through a provider of its own.
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
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
        home: const DockgeOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DockgeStack _stack(
  String name, {
  DockgeStackStatus status = DockgeStackStatus.running,
  List<String> tags = const [],
}) => DockgeStack(name: name, status: status, tags: tags);

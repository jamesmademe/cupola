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
  testWidgets('draws the regions in the order the narrow board draws them', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // What needs a decision, then the inventory. Agents is absent because this
    // Dockge has one instance.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs attention', 'Stacks'],
    );
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
      ['opens the Dockge Stacks tab', 'opens the Dockge Stacks tab'],
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

  testWidgets('an exited stack is a fault and speaks one sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        _stack('media'),
        _stack('bazarr', status: DockgeStackStatus.exited, tags: ['subs']),
      ],
    );

    // One node for the whole row, with the layout's dot read as a pause — not
    // three fragments a screen reader walks separately.
    expect(find.semantics.byLabel('Exited, bazarr, subs'), findsOneWidget);
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
    // wearing the same colour as one that died.
    expect(backlog.titleColor, neutral);
    expect(backlog.titleColor, isNot(amber));

    final fault = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(ServiceOverviewRow, 'Exited · bazarr'),
    );
    expect(fault.titleColor, amber);
  });

  testWidgets('the attention header counts every fault, not the rows it drew', (
    tester,
  ) async {
    await _pump(
      tester,
      stacks: [
        for (var i = 0; i < 6; i++)
          _stack('down-$i', status: DockgeStackStatus.exited),
        _stack('archive', status: DockgeStackStatus.createdFile),
        _stack('media'),
      ],
    );

    // Six faults, four rows drawn for them. The header is the only place the
    // remainder is reported, so it counts over the whole push — not the length
    // of the sample below it.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Needs attention'),
    );
    expect(header.subtitle, '6');
    expect(find.textContaining('Exited · '), findsNWidgets(4));
  });

  testWidgets('the attention header counts the faults, never the backlog', (
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

    // One crashed stack and eight templates nobody ever started. "9" here
    // would be the five-arm rule broken in the figure, over rows that got it
    // right: a tidy server reading as nine things on fire.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Needs attention'),
    );
    expect(header.subtitle, '1');
    // And the backlog is not silenced by that — it states its own size, in
    // words, in the neutral row that is about it.
    expect(find.text('8 stacks are inactive'), findsOneWidget);
  });

  testWidgets('a push that never arrived reads — and never 0', (tester) async {
    await _pump(tester, failStacks: true);

    // A "0" over an unanswered question claims every stack is up, which is the
    // reading the user would act on.
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failStacks: true);

    // Both stack regions fail together — they fold the same push — but each
    // says so in its own slot, and both headings survive.
    expect(find.byType(SectionHeader), findsNWidgets(2));
    expect(find.byType(AppErrorState), findsNWidgets(2));
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

    // The same guard the app-bar lens keeps: a picker — or a list — offering
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
    expect(agentsHeader.subtitle, '2 instances · 1 not answering');
    // No link and no picker: the lens is an app-bar control, and a second one
    // here would be two controls fighting over one piece of state.
    expect(agentsHeader.onTap, isNull);

    // And the stack census names the instance it was counted on — the client
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
    // Exited / Inactive off this same push. A subtitle spelling them again is
    // the same four figures twice in one screenful, wrapping to three lines
    // beside the "Stacks →" link — so on a single-instance Dockge with
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
    expect(header.subtitle, '7 instances · 2 not answering');
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

Future<void> _pump(
  WidgetTester tester, {
  List<DockgeStack> stacks = const [],
  List<DockgeAgent> agents = const [DockgeAgent.local],
  bool failStacks = false,
  bool online = true,
  bool configured = true,
  double textScaleFactor = 1.0,
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
      // tests below stop settling — which is the point of taking this out.
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

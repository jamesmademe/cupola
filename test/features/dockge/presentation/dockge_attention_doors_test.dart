/// What Dockge's Overview says is not running leads to where it is looked
/// after: a stack opens its own page, a row that sums several opens the Stacks
/// tab, and one stopped stack can be started from its row through the action
/// the Stacks tab and the stack's page already run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

DockgeStack _stack(String name, DockgeStackStatus status) =>
    DockgeStack(name: name, status: status, tags: const []);

void main() {
  testWidgets('P1: the stopped stack opens its page, and Start runs the same '
      'command the Stacks tab runs', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.followFakeTime(tester.binding);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final shell = OverviewShell(
      ServiceKey.dockge,
      const DockgeOverviewScreen(topPadding: 0),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: harness.overrides, child: shell.app),
    );
    await harness.settle(tester);

    // The world's Dockge has `immich` exited: one row, neutral, about it.
    expect(find.text('1 stack is stopped'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        '1 stack is stopped, immich, Dockge does not say why',
      ),
      containsSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens immich, with its log and controls',
      ),
    );
    expect(
      find.semantics.byHint('starts immich'),
      containsSemantics(label: 'Start', isButton: true, hasTapAction: true),
    );

    // Start is the stack's own command, and nothing else moved.
    await tester.tap(find.text('Start'));
    await harness.settle(tester);
    expect(
      harness.network.rpcCalls.where((call) => call.$2 == 'agent:startStack'),
      hasLength(1),
    );
    expect(find.text('Started immich'), findsOneWidget);
    expect(shell.tab, ServiceTab.overview);

    // The row's body, not the verb, is the way to the stack's page.
    await tester.tap(find.text('1 stack is stopped'));
    await harness.settle(tester);
    expect(shell.location, '/stack/dockge/stacks/stack/immich');
    expect(
      harness.network.rpcCalls.where((call) => call.$2 == 'agent:startStack'),
      hasLength(1),
      reason: 'opening the page does not start it again',
    );

    await harness.unmount(tester);
  });

  group('rows that sum several stacks', () {
    Future<OverviewShell> pump(
      WidgetTester tester,
      List<DockgeStack> stacks,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shell = OverviewShell(
        ServiceKey.dockge,
        const DockgeOverviewScreen(topPadding: 0),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => settingsWith(
                dockgeUrl: 'http://dockge.lan:5001',
                dockgeUsername: 'admin',
                dockgePassword: 'secret',
              ),
            ),
            dockgeStackListProvider.overrideWith((ref) => Stream.value(stacks)),
            dockgeAgentsProvider.overrideWith(
              (ref) => Stream.value(const [DockgeAgent.local]),
            ),
            serviceSummaryProvider.overrideWith(
              (ref, service) async => ServiceSummary(
                service: service,
                status: ServiceSummaryStatus.online,
                host: 'dockge.lan:5001',
                version: '1.5.0',
              ),
            ),
            serviceKpiProvider.overrideWith(
              (ref, service) async => const <ServiceKpi>[],
            ),
          ],
          child: shell.app,
        ),
      );
      await tester.pumpAndSettle();
      return shell;
    }

    testWidgets('several stopped stacks are one row: no single stack to open '
        'or start, so it opens the Stacks tab', (tester) async {
      final shell = await pump(tester, [
        _stack('media', DockgeStackStatus.running),
        _stack('bazarr', DockgeStackStatus.exited),
        _stack('immich', DockgeStackStatus.exited),
      ]);

      expect(find.text('2 stacks are stopped'), findsOneWidget);
      expect(
        find.semantics.byLabel(
          '2 stacks are stopped, bazarr, immich, Dockge does not say why',
        ),
        containsSemantics(isButton: true, hint: 'opens the Dockge Stacks tab'),
      );
      // Nothing to start: which one would it be.
      expect(find.text('Start'), findsNothing);

      await tester.tap(find.text('2 stacks are stopped'));
      await tester.pumpAndSettle();
      expect(shell.tab, ServiceTab.stacks);
    });

    testWidgets('one inactive stack opens its page and is not offered a '
        'start: it was brought down, or never started', (tester) async {
      final shell = await pump(tester, [
        _stack('media', DockgeStackStatus.running),
        _stack('draft', DockgeStackStatus.createdFile),
      ]);

      expect(find.text('1 stack is inactive'), findsOneWidget);
      expect(find.text('Start'), findsNothing);

      await tester.tap(find.text('1 stack is inactive'));
      await tester.pumpAndSettle();
      expect(shell.location, '/stack/dockge/stacks/stack/draft');
    });

    testWidgets('a running stack is a door to its page, as it was', (
      tester,
    ) async {
      final shell = await pump(tester, [
        _stack('media', DockgeStackStatus.running),
      ]);

      expect(
        find.semantics.byLabel('media, running'),
        containsSemantics(
          isButton: true,
          hint: 'opens media, with its log and controls',
        ),
      );
      await tester.tap(find.text('media'));
      await tester.pumpAndSettle();
      expect(shell.location, '/stack/dockge/stacks/stack/media');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/overview_shell.dart';
import '../test_helpers/profiles/profiles.dart';

/// Dockge once the world lives: a stack started from its row runs, and the
/// Overview stops saying it is stopped.
void main() {
  testWidgets('a stopped stack started in a living world runs', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network
      ..live()
      ..followFakeTime(tester.binding);
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
    expect(find.text('1 stack is stopped'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await harness.settle(tester);
    expect(find.text('1 stack is stopped'), findsNothing);

    await harness.unmount(tester);
  });
}

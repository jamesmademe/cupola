import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/truenas/presentation/reporting/truenas_reporting_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The Reporting page used to read every failure as an empty answer: the
/// reporting API caught the batch, fell back graph by graph, caught those too
/// and returned `[]`, so a TrueNAS that was down drew "No reporting data
/// available.": a statement about the server's graphs that nobody made.
void main() {
  const empty = 'No reporting data available.';

  testWidgets('a TrueNAS that did not answer is a fault, not an empty page', (
    tester,
  ) async {
    // P7 is away from home, and its TrueNAS answers only at home.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p7,
      child: const TrueNasReportingScreen(),
    );

    expect(find.text(empty), findsNothing);
    expect(find.byType(ServiceOfflineState), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('graphs the server refused, every one, are a fault too', (
    tester,
  ) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.onRpc(
      WorldIds.truenas,
      'reporting.get_data',
      (_) => throw const TrueNasRpcFault({
        'code': -32602,
        'message': 'Invalid params',
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const TrueNasReportingScreen(),
        ),
      ),
    );
    await harness.settle(tester);

    expect(find.text(empty), findsNothing);
    // The server answered, so this is the fault leaf with its reason, never
    // the red "did not answer" well.
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(ServiceOfflineState), findsNothing);

    await harness.unmount(tester);
  });
}

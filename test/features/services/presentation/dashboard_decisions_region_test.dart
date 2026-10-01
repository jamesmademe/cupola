/// Needs a decision, driven through the app's real clients on the profiles'
/// fake network: the region says three different things in three different
/// ways, and each source's decisions arrive when it does.
///
/// It used to draw nothing while loading, nothing when every source failed and
/// nothing when nothing was waiting — and to wait for the slowest source before
/// drawing anything at all.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);

Finder _inDecisions(Finder matching) => find.descendant(
  of: find.byType(DashboardDecisionsSection),
  matching: matching,
);

/// Starts [profile], lets [before] script the network, then pumps Home.
Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileNetwork network)? before,
  bool settle = true,
}) async {
  final harness = await ProfileHarness.start(profile);
  before?.call(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const DashboardScreen(),
      ),
    ),
  );
  if (settle) await harness.settle(tester);
  return harness;
}

/// Pumps [fakeTime] in small steps, yielding to the real event loop between
/// them so the fast sources' isolates answer — without waiting out a slow one.
Future<void> _advance(WidgetTester tester, Duration fakeTime) async {
  const step = Duration(milliseconds: 100);
  for (var elapsed = Duration.zero; elapsed < fakeTime; elapsed += step) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(step);
  }
}

void main() {
  testWidgets(
    'P1, Dockge slow: what answered is shown without waiting for it',
    (tester) async {
      final harness = await _pumpHome(
        tester,
        // Under Dockge's own ten-second deadline, so it does answer — late.
        Profiles.p1.withLatency(WorldIds.dockge, const Duration(seconds: 8)),
        settle: false,
      );

      await _advance(tester, const Duration(seconds: 3));

      // The stall and the blocked imports came off the queue in a few hundred
      // milliseconds; the region used to hold them back for Dockge's eight.
      expect(_inDecisions(find.text('Big Buck Bunny')), findsOne);
      expect(_inDecisions(find.text('18 need a manual import')), findsOne);
      // Dockge's stopped stack is not there yet, and nothing pretends it is.
      expect(_inDecisions(find.text('immich')), findsNothing);

      // Nothing animates while Dockge is out, so time has to be turned on
      // purpose rather than settled.
      await _advance(tester, const Duration(seconds: 7));
      await harness.settle(tester);
      expect(_inDecisions(find.text('immich')), findsOne);

      await harness.unmount(tester);
      // Every request to the slow host waits its eight seconds, the ones its
      // disposal sent included.
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets('P3, every source slow: a skeleton, never an absent region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const slow = Duration(seconds: 3);
    final harness = await _pumpHome(
      tester,
      Profiles.p3
          .withLatency(WorldIds.radarr, slow)
          .withLatency(WorldIds.sonarr, slow)
          .withLatency(WorldIds.seerr, slow),
      settle: false,
    );

    await _advance(tester, const Duration(seconds: 1));

    // Absence would say nothing needs you before anybody has been asked.
    expect(find.text('Needs a decision'), findsOne);
    expect(find.byType(DecisionRowSkeleton), findsOne);
    expect(find.bySemanticsLabel('Loading decisions'), findsOne);

    await harness.settle(tester);
    expect(find.byType(DecisionRowSkeleton), findsNothing);
    expect(_inDecisions(find.text('Metropolis')), findsOne);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P7, every source dark: one quiet line in red, with Retry', (
    tester,
  ) async {
    final harness = await _pumpHome(
      tester,
      Profiles.p7
          .withBehaviour(WorldIds.seerr, ConnectionBehaviour.didNotAnswer)
          .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
          .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer)
          .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.didNotAnswer),
    );

    final line = _inDecisions(find.byType(FaultBand));
    expect(line, findsOne);
    final band = tester.widget<FaultBand>(line);
    // The refusal is said in its own words; red because the rest are silent.
    expect(
      band.message,
      'Seerr, Radarr 1 and 6 others did not answer. qBittorrent answered but '
      'refused the sign-in.',
    );
    expect(band.tone, StatusTone.error);
    expect(_inDecisions(find.text('Retry')), findsOne);
    // No figure: nothing could be counted.
    expect(_inDecisions(find.textContaining('items')), findsNothing);
    expect(find.byType(DecisionRowSkeleton), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2, Seerr answering with an error: amber, and Retry asks Seerr '
      'again', (tester) async {
    var failing = true;
    final harness = await _pumpHome(
      tester,
      Profiles.p2,
      before: (network) => network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/request',
        (_) => failing
            ? NetworkReply.json({'message': 'Internal error'}, status: 500)
            : null,
      ),
    );

    final line = _inDecisions(find.byType(FaultBand));
    expect(line, findsOne);
    final band = tester.widget<FaultBand>(line);
    expect(band.message, 'Seerr answered with an error.');
    // Seerr answered: a fault, never red.
    expect(band.tone, StatusTone.warning);

    failing = false;
    await tester.tap(_inDecisions(find.text('Retry')));
    await harness.settle(tester);

    expect(_inDecisions(find.byType(FaultBand)), findsNothing);
    expect(_inDecisions(find.text('Metropolis')), findsOne);
    expect(_inDecisions(find.text('Charge')), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P1, SABnzbd back: the alert band Retry re-reads what every '
      'region holds of it', (tester) async {
    var down = true;
    final harness = await _pumpHome(
      tester,
      Profiles.p1,
      before: (network) {
        // A host that stopped answering, then came back: the dial fails the
        // way a refused connection does while [down], and answers after.
        NetworkReply? dead(NetworkRequest _) =>
            down ? throw const SocketException('Connection refused') : null;
        network
          ..on(WorldIds.sabnzbd, 'GET', RegExp('.*'), dead)
          ..on(WorldIds.sabnzbd, 'POST', RegExp('.*'), dead);
      },
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('services-alert-band')),
        matching: find.textContaining('SABnzbd did not answer.'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byType(ServicesInFlightSection),
        matching: find.text('Not in the total: SABnzbd'),
      ),
      findsOne,
    );
    // SABnzbd's rate is missing from the sum: its rows are joined to the 4K
    // Radarr's, and the rate is the part only SABnzbd can say.
    expect(find.textContaining('across 2 clients'), findsNothing);

    down = false;
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('services-alert-band')),
        matching: find.text('Retry'),
      ),
    );
    await harness.settle(tester);

    // The probe came back answering, and so did everything that reads it: the
    // band, the note under In flight, and SABnzbd's own rows.
    expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    expect(find.textContaining('Not in the total'), findsNothing);
    expect(find.text('5 downloading · 40 MB/s across 2 clients'), findsOne);

    await harness.unmount(tester);
  });
}

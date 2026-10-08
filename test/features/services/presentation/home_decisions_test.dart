/// What the Home says of the decisions it is waiting on, driven through the
/// app's real clients on the profiles' fake network: Needs you and Requests
/// say three different things in three different ways, and each source's
/// decisions arrive when it does.
///
/// They used to draw nothing while loading, nothing when every source failed
/// and nothing when nothing was waiting, and to wait for the slowest source
/// before drawing anything at all.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/decision_rows.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 6000);

Finder _inRows(Finder matching) =>
    find.descendant(of: find.byType(DecisionRow), matching: matching);

Finder _inNeedsYou(Finder matching) =>
    find.descendant(of: find.byType(NeedsYouLine), matching: matching);

Finder _inRequests(Finder matching) =>
    find.descendant(of: find.byType(HomeRequestsModule), matching: matching);

Finder _inDownloads(Finder matching) =>
    find.descendant(of: find.byType(HomeDownloadsModule), matching: matching);

/// Starts [profile], lets [before] script the network, then pumps [home].
///
/// The operator's Home, unless a test says otherwise: a requester's Home draws
/// two shelves in the modules' place, so a test about what a module says to a
/// requester mounts the module by itself.
Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileNetwork network)? before,
  bool settle = true,
  Widget home = const HomeScreen(),
}) async {
  final harness = await ProfileHarness.start(profile);
  before?.call(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: home),
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
        // The rows themselves: the Home leads with one line and no longer
        // lists the decisions, but they still arrive source by source.
        home: const Scaffold(body: ProvidedDecisionRows()),
      );

      await _advance(tester, const Duration(seconds: 3));

      // The stall and the blocked imports came off the queue in a few hundred
      // milliseconds; the rows used to be held back for Dockge's eight.
      expect(_inRows(find.text('Big Buck Bunny')), findsOne);
      expect(_inRows(find.text('18 need a manual import')), findsOne);
      // Dockge's stopped stack is not there yet, and nothing pretends it is.
      expect(_inRows(find.text('immich')), findsNothing);

      // Nothing animates while Dockge is out, so time has to be turned on
      // purpose rather than settled.
      await _advance(tester, const Duration(seconds: 7));
      await harness.settle(tester);
      expect(_inRows(find.text('immich')), findsOne);

      await harness.unmount(tester);
      // Every request to the slow host waits its eight seconds, the ones its
      // disposal sent included.
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets(
    'P1, Dockge slow: Needs you leads with what answered, and counts the '
    'rest as it arrives',
    (tester) async {
      final harness = await _pumpHome(
        tester,
        Profiles.p1.withLatency(WorldIds.dockge, const Duration(seconds: 8)),
        settle: false,
      );

      await _advance(tester, const Duration(seconds: 3));

      // The blocked imports lead and the stall is the one thing more: Dockge's
      // stopped stack is not counted until Dockge has said so.
      expect(
        _inNeedsYou(find.text('18 downloads need a manual import')),
        findsOne,
      );
      expect(_inNeedsYou(find.text('+1')), findsOne);

      await _advance(tester, const Duration(seconds: 7));
      await harness.settle(tester);
      // Dockge's own probe gave up before its list came: it is the silence
      // that leads now, and the stack it stopped is counted with the rest.
      expect(
        _inNeedsYou(find.textContaining(RegExp(r'^Dockge did not answer at '))),
        findsOne,
      );
      expect(_inNeedsYou(find.text('+3')), findsOne);

      await harness.unmount(tester);
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets('P3, every source slow: a skeleton in Requests, and no gap where '
      'Needs you will be', (tester) async {
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

    // Requests keeps its place with its name over the shape of its rows, so a
    // Home that has not heard from Seerr does not read as one with nothing
    // waiting. Needs you says nothing while nothing is known, and holds no
    // space for it.
    expect(find.text('Requests'), findsOne);
    expect(find.bySemanticsLabel('Loading requests'), findsOne);
    expect(find.byType(NeedsYouLine), findsNothing);

    // Nothing else on the Home animates while the three are out, so settling
    // alone would stop at the first quiet frame: their seconds are turned on
    // purpose, as in the Dockge test above. Seerr is read in two calls, one
    // after the other, each of them slow.
    await _advance(tester, const Duration(seconds: 12));
    await harness.settle(tester);
    expect(find.bySemanticsLabel('Loading requests'), findsNothing);
    expect(_inRequests(find.text('Metropolis')), findsOne);

    handle.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P7, every source dark: Needs you leads in red, with Retry', (
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

    expect(
      _inNeedsYou(
        find.textContaining(
          RegExp(
            r'^Seerr, Radarr, Sonarr and 7 others did not answer at '
            r'\d{2}:\d{2}$',
          ),
        ),
      ),
      findsOne,
    );
    // Red: a service that did not answer, never an amber fault.
    final context = tester.element(find.byType(NeedsYouLine));
    final glyph = tester.widget<Icon>(_inNeedsYou(find.byType(Icon)));
    expect(glyph.icon, Icons.cloud_off_rounded);
    expect(
      glyph.color,
      statusToneColor(
        Theme.of(context).colorScheme,
        StatusTone.error,
        surface: CupolaRoom.of(context).slab,
      ),
    );
    expect(_inNeedsYou(find.text('Retry')), findsOne);
    // No figure: nothing could be counted, so there is no `+N` either.
    expect(_inNeedsYou(find.textContaining(RegExp(r'^\+\d'))), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Loading')), findsNothing);

    // Seerr is one of the sources that did not answer, and Requests says so
    // in its place, in red like the rest, with its own Retry.
    final seerr = _inRequests(find.byType(FaultBand));
    expect(seerr, findsOne);
    expect(tester.widget<FaultBand>(seerr).message, 'Seerr did not answer.');
    expect(tester.widget<FaultBand>(seerr).tone, StatusTone.error);
    expect(_inRequests(find.text('Retry')), findsOne);
    // The refusal is said in its own words, where the queue is.
    final queue = _inDownloads(find.byType(FaultBand));
    expect(queue, findsOne);
    expect(
      tester.widget<FaultBand>(queue).message,
      'Radarr 1, Radarr 4K and 3 others did not answer. qBittorrent answered '
      'but refused the sign-in.',
    );
    expect(tester.widget<FaultBand>(queue).tone, StatusTone.error);

    await harness.unmount(tester);
  });

  testWidgets('P2, Seerr answering with an error: amber, and Retry asks Seerr '
      'again', (tester) async {
    var failing = true;
    final harness = await _pumpHome(
      tester,
      Profiles.p2,
      // The module alone: Anna's Home has her two shelves where it would be.
      home: const Scaffold(
        body: SingleChildScrollView(child: HomeRequestsModule()),
      ),
      before: (network) => network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/request',
        (_) => failing
            ? NetworkReply.json({'message': 'Internal error'}, status: 500)
            : null,
      ),
    );

    final line = _inRequests(find.byType(FaultBand));
    expect(line, findsOne);
    final band = tester.widget<FaultBand>(line);
    expect(band.message, 'Seerr answered with an error.');
    // Seerr answered: a fault, never red.
    expect(band.tone, StatusTone.warning);

    failing = false;
    await tester.tap(_inRequests(find.text('Retry')));
    await harness.settle(tester);

    // PORT: fails on lib, which is left as it is. Requests now reads the
    // waiting page (`pendingRequestsForProvider`), but Retry only drops what
    // `dashboardSourcesOf(ServiceKey.seerr)` lists
    // (lib/features/services/presentation/dashboard_retry.dart), which is
    // `requestsForProvider` and `servicesRequestsProvider`. The module
    // re-reads the failure it cached: expected no FaultBand after Retry, found
    // one. Listing `pendingRequestsForProvider` there makes this pass.
    expect(_inRequests(find.byType(FaultBand)), findsNothing);
    // Anna decides nothing: her own waiting Charge is no decision of hers,
    // and Luca's Metropolis is not hers to see.
    expect(_inRequests(find.text('Charge')), findsNothing);
    expect(_inRequests(find.text('Metropolis')), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1, SABnzbd back: the Needs you Retry re-reads what every '
      'module holds of it', (tester) async {
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
      _inNeedsYou(
        find.textContaining(RegExp(r'^SABnzbd did not answer at \d{2}:\d{2}$')),
      ),
      findsOne,
    );
    expect(_inDownloads(find.text('Not in the total: SABnzbd')), findsOne);
    // SABnzbd's rate is missing from the sum: its rows are joined to the 4K
    // Radarr's, and the rate is the part only SABnzbd can say. The speed is a
    // dash, not the half of it that qBittorrent reported.
    expect(_inDownloads(find.text('5 moving · 1 stuck · —')), findsOne);
    expect(_inDownloads(find.textContaining('MB/s')), findsNothing);

    down = false;
    await tester.tap(_inNeedsYou(find.text('Retry')));
    await harness.settle(tester);

    // The probe came back answering, and so did everything that reads it:
    // Needs you, the note under Downloads, and SABnzbd's own rows.
    expect(find.textContaining('did not answer'), findsNothing);
    expect(find.textContaining('Not in the total'), findsNothing);
    expect(
      _inDownloads(find.text('5 moving · 1 stuck · 40.4\u00A0MB/s')),
      findsOne,
    );

    await harness.unmount(tester);
  });
}

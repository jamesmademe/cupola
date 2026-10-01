/// A region's Retry asks its failed sources again, driven through the app's
/// real clients on the profiles' fake network.
///
/// In flight's and Recently added's Retry used to drop the summary and the
/// merge. The summary only delegates to the probe it awaits, and the merge
/// awaits client queues that hold a failure until somebody drops them, so a
/// recovered qBittorrent stayed missing from the queue and a recovered Radarr
/// stayed named in the band above.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Hosts that stop answering, then come back: while [down] says so, every
/// request to them fails the way a refused connection does.
void _goneWhile(
  ProfileNetwork network,
  Iterable<String> ids,
  bool Function() down,
) {
  NetworkReply? dead(NetworkRequest _) =>
      down() ? throw const SocketException('Connection refused') : null;
  for (final id in ids) {
    network
      ..on(id, 'GET', RegExp('.*'), dead)
      ..on(id, 'POST', RegExp('.*'), dead);
  }
}

Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile, {
  required void Function(ProfileNetwork network) before,
}) async {
  final harness = await ProfileHarness.start(profile);
  before(harness.network);
  await tester.binding.setSurfaceSize(const Size(430, 6000));
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
  await harness.settle(tester);
  return harness;
}

Finder _within(Type region, Finder matching) =>
    find.descendant(of: find.byType(region), matching: matching);

void main() {
  testWidgets('P1, every queue back: In flight Retry brings back every '
      'client, not only the arrs', (tester) async {
    var down = true;
    final harness = await _pumpHome(
      tester,
      Profiles.p1,
      before: (network) => _goneWhile(network, const [
        WorldIds.radarr,
        WorldIds.radarr4k,
        WorldIds.sonarr,
        WorldIds.lidarr,
        WorldIds.qbittorrent,
        WorldIds.sabnzbd,
      ], () => down),
    );

    expect(find.text('— downloading'), findsOne);
    expect(_within(ServicesInFlightSection, find.byType(FaultBand)), findsOne);

    down = false;
    await tester.tap(_within(ServicesInFlightSection, find.text('Retry')));
    await harness.settle(tester);

    // The arrs' queues are read straight off their clients and came back with
    // the merge; qBittorrent's and SABnzbd's are providers of their own that
    // kept the failure, and only dropping them brings their rows back.
    expect(
      _within(ServicesInFlightSection, find.byType(FaultBand)),
      findsNothing,
    );
    expect(find.text('5 downloading · 40 MB/s across 2 clients'), findsOne);
    expect(find.textContaining('not in the total'), findsNothing);
    expect(find.text('Elephants.Dream.2006.2160p.UHD.BluRay'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P1, the arrs back: Recently added Retry re-asks whether they '
      'answer, so the band lets go of them', (tester) async {
    var down = true;
    final harness = await _pumpHome(
      tester,
      Profiles.p1,
      before: (network) => _goneWhile(network, const [
        WorldIds.radarr,
        WorldIds.radarr4k,
        WorldIds.sonarr,
        WorldIds.lidarr,
      ], () => down),
    );

    expect(find.text('— imported'), findsOne);
    expect(
      find.byKey(const ValueKey('services-alert-band')),
      findsOne,
      reason: 'the probes found the three arrs dark',
    );

    down = false;
    await tester.tap(_within(ServicesRecentlyAddedSection, find.text('Retry')));
    await harness.settle(tester);

    expect(find.text('5 imported'), findsOne);
    // The probe itself was asked, not the summary that awaits its old answer.
    expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    expect(find.textContaining('did not answer'), findsNothing);

    await harness.unmount(tester);
  });
}

/// A client's page says since when its service has not answered.
///
/// Driven through the app's real probe on the profiles' fake network: the page
/// is built on `serviceSummaryProvider`, the probe notes the silence, and the
/// band over a queue already read (or the leaf, on a cold open) says how long.
/// The time is the first one the probe did not answer at, however many times
/// it is asked again, and the page loses it the moment the service answers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

typedef _Page = ({
  String name,
  ServiceKey service,
  String id,
  ConfigProfile profile,
  Widget Function() screen,
  Type type,
});

final _pages = <_Page>[
  (
    name: 'SABnzbd',
    service: ServiceKey.sabnzbd,
    id: WorldIds.sabnzbd,
    profile: Profiles.p1,
    screen: () => const SabnzbdScreen(),
    type: SabnzbdScreen,
  ),
  (
    name: 'NZBGet',
    service: ServiceKey.nzbget,
    id: WorldConnections.nzbget.id,
    profile: Profiles.p1.withConnection(WorldConnections.nzbget),
    screen: () => const NzbgetScreen(),
    type: NzbgetScreen,
  ),
  (
    name: 'Transmission',
    service: ServiceKey.transmission,
    id: WorldIds.transmission,
    profile: Profiles.p1.withConnection(WorldConnections.transmission),
    screen: () => const TransmissionScreen(),
    type: TransmissionScreen,
  ),
  (
    name: 'Unraid',
    service: ServiceKey.unraid,
    id: WorldConnections.unraid.id,
    profile: Profiles.p1.withConnection(WorldConnections.unraid),
    screen: () => const UnraidScreen.array(),
    type: UnraidScreen,
  ),
  (
    name: 'Nginx Proxy Manager',
    service: ServiceKey.nginxProxyManager,
    id: WorldConnections.npm.id,
    profile: Profiles.p1.withConnection(WorldConnections.npm),
    screen: () => const NpmScreen(),
    type: NpmScreen,
  ),
];

void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 12, 20, 41);
    PollProbe.instance.reset();
  });

  Future<(ProfileHarness, ProviderContainer)> open(
    WidgetTester tester,
    _Page page, {
    required ConnectionBehaviour behaviour,
  }) async {
    final harness = await pumpWithProfile(
      tester,
      page.profile.withBehaviour(page.id, behaviour),
      child: page.screen(),
      surfaceSize: const Size(390, 2400),
      overrides: [
        readClockProvider.overrideWithValue(ReadClock(now: () => now)),
      ],
    );
    return (
      harness,
      ProviderScope.containerOf(tester.element(find.byType(page.type))),
    );
  }

  /// The probe asked again, as a Retry, a pull or the Home's recovery poll
  /// does, and the page given the time to draw what came back.
  Future<void> askAgain(
    WidgetTester tester,
    ProfileHarness harness,
    ProviderContainer container,
    _Page page,
  ) async {
    container.invalidate(
      instanceSummaryProvider((service: page.service, instanceId: page.id)),
    );
    await harness.settle(tester);
    // A client's queue reads itself again on its own tick: its list, failed
    // while the server was quiet, is read again within one.
    await tester.pump(const Duration(seconds: 3));
    await harness.settle(tester);
  }

  /// A minute of the page's own clock: the span it prints is renewed once a
  /// minute, so a page left on screen moves with the time without being asked.
  Future<void> minutesPass(WidgetTester tester, int minutes) async {
    now = now.add(Duration(minutes: minutes));
    await tester.pump(const Duration(minutes: 1));
  }

  for (final page in _pages) {
    group('${page.name}, with nothing read yet', () {
      testWidgets('says since when it has not answered, from the first '
          'probe', (tester) async {
        final (harness, container) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.didNotAnswer,
        );

        // A cold start into a silent service: the first probe of the run is
        // the first time the app saw it silent, and under a minute the leaf
        // drops the span rather than print a number nobody can act on.
        expect(find.byType(ServiceOfflineState), findsOneWidget);
        expect(find.textContaining('did not answer'), findsWidgets);
        expect(find.textContaining('has not answered for'), findsNothing);

        await minutesPass(tester, 6);
        expect(
          find.textContaining('It has not answered for 6 minutes.'),
          findsOneWidget,
        );

        // Asked again, and silent again: the same silence, not a new one.
        await askAgain(tester, harness, container, page);
        expect(
          find.textContaining('It has not answered for 6 minutes.'),
          findsOneWidget,
        );
        await minutesPass(tester, 5);
        expect(
          find.textContaining('It has not answered for 11 minutes.'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });

      testWidgets('loses it when the service answers again', (tester) async {
        final (harness, container) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.didNotAnswer,
        );
        await minutesPass(tester, 6);
        expect(find.textContaining('has not answered for'), findsOneWidget);

        harness.network.behave(page.id, ConnectionBehaviour.answers);
        await askAgain(tester, harness, container, page);

        expect(find.byType(ServiceOfflineState), findsNothing);
        expect(find.byType(FaultBand), findsNothing);
        expect(find.textContaining('has not answered for'), findsNothing);

        await harness.unmount(tester);
      });

      testWidgets('says nothing of how long when the service answered, and '
          'refused', (tester) async {
        final (harness, container) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.didNotAnswer,
        );
        await minutesPass(tester, 6);

        // An answer that says something is wrong is still an answer: amber,
        // and no clock that says the box has been dark.
        harness.network.behave(page.id, ConnectionBehaviour.refusesKey);
        await askAgain(tester, harness, container, page);

        expect(find.textContaining('has not answered for'), findsNothing);

        await harness.unmount(tester);
      });
    });

    group('${page.name}, Retry', () {
      /// What the person taps: the page's own Retry, on the leaf or the band.
      Future<void> retry(WidgetTester tester, ProfileHarness harness) async {
        await tester.ensureVisible(find.text('Retry').first);
        await tester.tap(find.text('Retry').first);
        await harness.settle(tester);
      }

      testWidgets('asks the server again, and a server that answers ends '
          'the leaf', (tester) async {
        final (harness, _) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.didNotAnswer,
        );
        await minutesPass(tester, 6);
        expect(find.byType(ServiceOfflineState), findsOneWidget);

        harness.network.behave(page.id, ConnectionBehaviour.answers);
        await retry(tester, harness);

        // Neither the leaf nor, once the page has something to keep, a band
        // over it: the probe was asked again and said the server is back.
        expect(find.byType(ServiceOfflineState), findsNothing);
        expect(find.byType(FaultBand), findsNothing);
        expect(find.textContaining('has not answered for'), findsNothing);

        await harness.unmount(tester);
      });

      testWidgets('that fails again is the same silence, not a new one', (
        tester,
      ) async {
        final (harness, _) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.didNotAnswer,
        );
        await minutesPass(tester, 6);

        await retry(tester, harness);

        expect(
          find.textContaining('It has not answered for 6 minutes.'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });

      testWidgets('asks the server again over what was read, and a server '
          'that answers ends the band', (tester) async {
        final (harness, container) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.answers,
        );
        harness.network.behave(page.id, ConnectionBehaviour.didNotAnswer);
        await askAgain(tester, harness, container, page);
        await minutesPass(tester, 6);
        expect(find.byType(FaultBand), findsOneWidget);

        harness.network.behave(page.id, ConnectionBehaviour.answers);
        await retry(tester, harness);

        expect(find.byType(FaultBand), findsNothing);

        await harness.unmount(tester);
      });
    });

    group('${page.name}, over what it read before it went quiet', () {
      /// The page has read what it reads while the service answered; then
      /// the service goes quiet and the probe says so.
      Future<(ProfileHarness, ProviderContainer)> goQuiet(
        WidgetTester tester,
      ) async {
        final (harness, container) = await open(
          tester,
          page,
          behaviour: ConnectionBehaviour.answers,
        );
        expect(find.byType(FaultBand), findsNothing);
        harness.network.behave(page.id, ConnectionBehaviour.didNotAnswer);
        await askAgain(tester, harness, container, page);
        return (harness, container);
      }

      testWidgets('the band says since when, and keeps the first time '
          'across retries', (tester) async {
        final (harness, container) = await goQuiet(tester);

        expect(find.byType(FaultBand), findsOneWidget);
        expect(find.textContaining('did not answer'), findsOneWidget);
        expect(find.textContaining('has not answered for'), findsNothing);

        await minutesPass(tester, 6);
        expect(
          find.textContaining(
            '${page.service.title} has not answered for 6 minutes',
          ),
          findsOneWidget,
        );

        await askAgain(tester, harness, container, page);
        await minutesPass(tester, 4);
        expect(
          find.textContaining(
            '${page.service.title} has not answered for 10 minutes',
          ),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });

      testWidgets('the band goes, and its time with it, when the service '
          'answers again', (tester) async {
        final (harness, container) = await goQuiet(tester);
        await minutesPass(tester, 6);
        expect(find.byType(FaultBand), findsOneWidget);

        harness.network.behave(page.id, ConnectionBehaviour.answers);
        await askAgain(tester, harness, container, page);

        expect(find.byType(FaultBand), findsNothing);
        expect(find.textContaining('has not answered for'), findsNothing);

        // Quiet again later: a new silence, from its own first time.
        harness.network.behave(page.id, ConnectionBehaviour.didNotAnswer);
        await askAgain(tester, harness, container, page);
        expect(find.byType(FaultBand), findsOneWidget);
        expect(find.textContaining('has not answered for'), findsNothing);
        await minutesPass(tester, 2);
        expect(
          find.textContaining(
            '${page.service.title} has not answered for 2 minutes',
          ),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });
    });
  }
}

/// The network faults in front of a service: I-20.
///
/// The world: Radarr behind its Toxiproxy listener ([PROXIES] in the lab's
/// own tooling), the app pointed at the proxy by the profile the harness
/// writes, and the fault injected through the lab's control API. A journey on
/// the simulator cannot start a process, but the control API is an HTTP
/// request, so the world changes from inside the journey and the app's own
/// reading of it is what is asserted.
///
/// What this proves, in the app's own words:
///
/// - **I-20**: a service whose socket is reset reads red, `Radarr did not
///   answer`, and never claims a refused key; a host that stalls is silence
///   too, because the 1.5 s route knock is what decides the connection is
///   there; and `clear` plus the band's `Retry` puts the page back to its
///   library.
@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'I-20 · a service that does not answer, one that stalls, and the way back',
    (tester) async {
      IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final app = await LabApp.asOperator(
        tester,
        services: const {ServiceKey.radarr},
      );
      addTearDown(() => app.command(['fault', 'radarr', 'clear']));

      // Nothing at the socket: the address is reset, which is red and is the
      // service's silence, never a key the server refused.
      await app.command(['fault', 'radarr', 'down']);
      await app.go(tester, ServiceRoutes.radarrOverview);
      await app.surface.seePart('Radarr did not answer');
      await app.surface.see('Retry');
      expect(
        app.surface.drawsPart('refused the'),
        isFalse,
        reason: 'a socket that resets is silence, not a refusal',
      );

      // The network answers again: the band's own Retry is all it takes.
      await app.command(['fault', 'radarr', 'clear']);
      await tester.tap(find.text('Retry').first);
      await settle(tester, const Duration(seconds: 8));
      expect(app.surface.drawsPart('did not answer'), isFalse);
      await app.surface.see('Recently added');

      // A host that stalls, before its route has been proven, is silence: the
      // 1.5 s knock is what decides whether the connection is there, so a
      // 25 s answer reads red, not amber. (`Radarr was reached but did not
      // reply in time` needs a route already proven and a read that then
      // hangs; a proxy that stalls everything stalls the knock too, so that
      // sentence stays a unit-level promise of `failureHeadline`.)
      await app.command(['fault', 'radarr', 'slow', '25000']);
      await app.go(tester, ServiceRoutes.radarrOverview);
      await tester.fling(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 500),
        1000,
      );
      await settle(tester, const Duration(seconds: 2));
      await app.surface.seePart('Radarr did not answer');

      // The stall lifts, and the page reads its library again.
      await app.command(['fault', 'radarr', 'clear']);
      await tester.tap(find.text('Retry').first);
      await settle(tester, const Duration(seconds: 8));
      expect(app.surface.drawsPart('did not answer'), isFalse);
      await app.surface.see('Recently added');
    },
  );
}

/// The gate a surface reads, per Seerr connection: who the app is for, what
/// the connection may do, and the server it is on.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who the app is for', () {
    for (final (profile, audience) in [
      (Profiles.p1, Audience.operator),
      (Profiles.p2, Audience.requester),
      (Profiles.p2ViaJellyfin, Audience.requester),
      (Profiles.p2ViaPlex, Audience.requester),
      // Her own Jellyfin is a player she watches with, not a stack she runs.
      (Profiles.p2WithJellyfin, Audience.requester),
      // A friend's Seerr beside the household's own key.
      (Profiles.p9, Audience.operator),
    ]) {
      test('${profile.id}: ${audience.name}', () async {
        final harness = await ProfileHarness.start(profile);
        expect(harness.container().read(audienceProvider), audience);
        // Read from the saved settings alone.
        expect(harness.network.requests, isEmpty);
      });
    }

    test('signing out does not make anyone the operator', () async {
      final harness = await ProfileHarness.start(
        Profiles.p2.withSeerrSignedOut(WorldIds.seerr),
      );
      expect(harness.container().read(audienceProvider), Audience.requester);
    });

    test('a service of her own makes her the operator', () async {
      final harness = await ProfileHarness.start(
        Profiles.p2.withConnection(WorldConnections.radarr),
      );
      expect(harness.container().read(audienceProvider), Audience.operator);
    });

    test('promoted to manage requests, she is the operator', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final container = harness.container();
      expect(container.read(audienceProvider), Audience.requester);

      await container.read(seerrAccountsProvider).recordWhoAmI(WorldIds.seerr, {
        'permissions': SeerrPermission.manageRequests.value,
      });

      expect(container.read(audienceProvider), Audience.operator);
    });
  });

  group('the gate of one Seerr', () {
    test(
      'the requester: her own controls live, the operator\'s absent',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2);
        final container = harness.container(retry: (_, _) => null);
        final gate = container.read(roleGateProvider(''));

        expect(gate.audience, Audience.requester);
        expect(gate.requestAction(SeerrMediaKind.movie), const Live());
        expect(gate.operatorAction(SeerrAbility.approve), const Absent());
        expect(gate.operatorAction(SeerrAbility.manageMedia), const Absent());
        expect(gate.showsRequesterNames, isFalse);
        expect(gate.namesService(ServiceKey.seerr), isFalse);
        expect(gate.faultVoice, FaultVoice.brief);
        // The lens and the connection by name are one gate.
        expect(container.read(roleGateProvider(WorldIds.seerr)), gate);
      },
    );

    test('the operator: the key live, the friend\'s account dimmed', () async {
      final harness = await ProfileHarness.start(Profiles.p9);
      final container = harness.container(retry: (_, _) => null);

      final own = container.read(roleGateProvider(WorldIds.seerr));
      expect(own.operatorAction(SeerrAbility.approve), const Live());
      expect(own.showsRequesterNames, isTrue);
      expect(own.faultVoice, FaultVoice.full);

      final friend = container.read(roleGateProvider(WorldIds.seerrFriend));
      expect(friend.operatorAction(SeerrAbility.approve), isA<Dimmed>());
      expect(
        friend.operatorAction(SeerrAbility.approve).reason,
        "Your account on Seerr can't approve requests.",
      );
      expect(friend.showsRequesterNames, isFalse);
      expect(friend.namesService(ServiceKey.radarr), isTrue);
    });

    test(
      'the key asks the server nothing; an account reads its facts',
      () async {
        final harness = await ProfileHarness.start(Profiles.p9);
        final container = harness.container(retry: (_, _) => null);

        final own = container.listen(
          roleGateProvider(WorldIds.seerr),
          (_, _) {},
        );
        await Future<void>.delayed(Duration.zero);
        expect(own.read().server, isNull);
        expect(harness.network.requestsTo(WorldIds.seerr), isEmpty);

        final friend = container.listen(
          roleGateProvider(WorldIds.seerrFriend),
          (_, _) {},
        );
        await container.read(
          seerrServerFactsProvider(WorldIds.seerrFriend).future,
        );
        expect(friend.read().server, isNotNull);
        expect(
          harness.network
              .requestsTo(WorldIds.seerrFriend)
              .map((request) => request.path),
          containsAll(['/api/v1/status', '/api/v1/settings/public']),
        );
      },
    );

    test('a signed-out account asks its server nothing', () async {
      final harness = await ProfileHarness.start(
        Profiles.p2.withSeerrSignedOut(WorldIds.seerr),
      );
      final container = harness.container(retry: (_, _) => null);
      final gate = container.listen(roleGateProvider(''), (_, _) {});
      await Future<void>.delayed(Duration.zero);

      expect(gate.read().server, isNull);
      expect(gate.read().grant, isA<SeerrGrant>());
      expect(harness.network.requests, isEmpty);
    });

    test('no Seerr: the audience alone decides', () async {
      final harness = await ProfileHarness.start(Profiles.p4);
      final gate = harness.container().read(roleGateProvider(''));
      expect(gate.grant, isNull);
      expect(gate.operatorAction(SeerrAbility.approve), const Live());
    });
  });
}

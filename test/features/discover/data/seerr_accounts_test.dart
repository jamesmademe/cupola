/// What an account may do and how much it may still ask for, kept current:
/// the grant from the saved permissions, `/auth/me` read again at start and
/// when it is stale, and the quota read each time it is asked.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

int _whoAmIs(ProfileHarness harness, String id) => harness.network
    .requestsTo(id)
    .where((r) => r.path == '/api/v1/auth/me')
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the grant', () {
    test('the key may do everything; an account what it saved', () async {
      final harness = await ProfileHarness.start(Profiles.p9);
      final container = harness.container();

      expect(
        container.read(seerrGrantProvider(WorldIds.seerr)),
        const SeerrGrant.apiKey(),
      );
      expect(
        container.read(seerrGrantProvider(WorldIds.seerrFriend)),
        SeerrGrant.account(permissions: SeerrPermission.request.value),
      );
      // Empty is the lens, the household's Seerr.
      expect(container.read(seerrGrantProvider('')), const SeerrGrant.apiKey());
      expect(container.read(seerrGrantProvider('no-such-seerr')), isNull);
      // Nothing was asked for it: the saved permissions are the first frame.
      expect(harness.network.requests, isEmpty);
    });

    test(
      'follows /auth/me when the operator changes the permissions',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2);
        final container = harness.container();
        expect(
          container.read(seerrGrantProvider(WorldIds.seerr))!.role,
          SeerrRole.requester,
        );

        await container.read(seerrAccountsProvider).recordWhoAmI(
          WorldIds.seerr,
          {'permissions': SeerrPermission.manageRequests.value},
        );

        expect(
          container.read(seerrGrantProvider(WorldIds.seerr))!.role,
          SeerrRole.manager,
        );
      },
    );
  });

  group('reading /auth/me again', () {
    test('every signed-in account, at start', () async {
      final harness = await ProfileHarness.start(
        Profiles.p9.withSeerrPermissions(
          SeerrPermission.request.value | SeerrPermission.autoApprove.value,
        ),
      );
      final container = harness.container();

      await container.read(seerrAccountsProvider).refreshAll();

      // The friend's Seerr, the one account; the household's key has none.
      expect(_whoAmIs(harness, WorldIds.seerrFriend), 1);
      expect(_whoAmIs(harness, WorldIds.seerr), 0);
      final account = container
          .read(currentSettingsProvider)
          .instanceById(WorldIds.seerrFriend)!
          .account!;
      expect(account.permissions, 160);
      expect(account.checkedAt, isNotNull);
    });

    test('coming back, only what is older than fifteen minutes', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final container = harness.container();
      final accounts = container.read(seerrAccountsProvider);
      await accounts.refreshAll();
      expect(_whoAmIs(harness, WorldIds.seerr), 1);

      await accounts.refreshAll(olderThan: seerrPermissionsMaxAge);

      expect(_whoAmIs(harness, WorldIds.seerr), 1, reason: 'read just now');
    });

    test('an ended session found at start signs the account out', () async {
      final harness = await ProfileHarness.start(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.sessionExpired,
        ),
      );
      final container = harness.container();

      await container.read(seerrAccountsProvider).refreshAll();
      await Future<void>.delayed(Duration.zero);

      final seerr = container
          .read(currentSettingsProvider)
          .instanceById(WorldIds.seerr)!;
      expect(seerr.isSignedOut, isTrue);
    });

    test('the app root starts it once', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final container = harness.container();

      container.read(seerrAccountKeeperProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(_whoAmIs(harness, WorldIds.seerr), 1);
    });
  });

  group('the quota', () {
    test('read for an account, never for the key', () async {
      final harness = await ProfileHarness.start(
        Profiles.p9.withBehaviour(
          WorldIds.seerrFriend,
          ConnectionBehaviour.quotaReached,
        ),
      );
      final container = harness.container(retry: (_, _) => null);

      final friend = await container.read(
        seerrQuotaProvider(WorldIds.seerrFriend).future,
      );
      final own = await container.read(
        seerrQuotaProvider(WorldIds.seerr).future,
      );

      expect(friend?.movie.restricted, isTrue);
      expect(friend?.movie.limit, 5);
      expect(own, isNull);
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.path.contains('/quota')),
        isEmpty,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';

int _bits(List<SeerrPermission> permissions) =>
    permissions.fold(0, (mask, permission) => mask | permission.value);

/// The masks every ability is asked about, one column each.
final _masks = <(String, int)>[
  ('0', 0),
  ('REQUEST', _bits([SeerrPermission.request])),
  ('REQUEST_MOVIE', _bits([SeerrPermission.requestMovie])),
  ('REQUEST_TV', _bits([SeerrPermission.requestTv])),
  (
    'REQUEST|REQUEST_4K',
    _bits([SeerrPermission.request, SeerrPermission.request4k]),
  ),
  ('REQUEST_4K_MOVIE', _bits([SeerrPermission.request4kMovie])),
  ('AUTO_APPROVE', _bits([SeerrPermission.autoApprove])),
  ('AUTO_APPROVE_TV', _bits([SeerrPermission.autoApproveTv])),
  ('AUTO_APPROVE_4K_MOVIE', _bits([SeerrPermission.autoApprove4kMovie])),
  ('REQUEST_ADVANCED', _bits([SeerrPermission.requestAdvanced])),
  ('REQUEST_VIEW', _bits([SeerrPermission.requestView])),
  ('MANAGE_REQUESTS', _bits([SeerrPermission.manageRequests])),
  ('MANAGE_USERS', _bits([SeerrPermission.manageUsers])),
  ('VIEW_ISSUES', _bits([SeerrPermission.viewIssues])),
  ('CREATE_ISSUES', _bits([SeerrPermission.createIssues])),
  ('MANAGE_ISSUES', _bits([SeerrPermission.manageIssues])),
  ('ADMIN', _bits([SeerrPermission.admin])),
];

/// Seerr v3.5.0's own rule for each ability, written by hand from the source
/// and not from the code under test. One column per mask in [_masks]:
///
///     0  REQUEST  REQUEST_MOVIE  REQUEST_TV  REQUEST|REQUEST_4K
///     REQUEST_4K_MOVIE  AUTO_APPROVE  AUTO_APPROVE_TV  AUTO_APPROVE_4K_MOVIE
///     REQUEST_ADVANCED  REQUEST_VIEW  MANAGE_REQUESTS  MANAGE_USERS
///     VIEW_ISSUES  CREATE_ISSUES  MANAGE_ISSUES  ADMIN
///
/// `-` no, `M` for a movie only, `T` for a series only, `A` for both.
const _table = <SeerrAbility, String>{
  // `server/entity/MediaRequest.ts:107-139`: REQUEST or REQUEST_MOVIE/_TV.
  // MANAGE_REQUESTS alone may not ask.
  SeerrAbility.request: '- A M T A - - - - - - - - - - - A',
  // `MediaRequest.ts:110-111,126-127`: REQUEST_4K or REQUEST_4K_MOVIE/_TV,
  // without REQUEST.
  SeerrAbility.request4k: '- - - - A M - - - - - - - - - - A',
  // `MediaRequest.ts:316-327,431-442`: AUTO_APPROVE, AUTO_APPROVE_MOVIE/_TV
  // or MANAGE_REQUESTS.
  SeerrAbility.autoApproved: '- - - - - - A T - - - A - - - - A',
  // The same lines with the 4K bits. AUTO_APPROVE does not cover 4K.
  SeerrAbility.autoApproved4k: '- - - - - - - - M - - A - - - - A',
  // `MediaRequest.ts:276-279`: MANAGE_REQUESTS or REQUEST_ADVANCED.
  SeerrAbility.chooseDestination: '- - - - - - - - - A - A - - - - A',
  // `MediaRequest.ts:143`: MANAGE_REQUESTS.
  SeerrAbility.bypassQuota: '- - - - - - - - - - - A - - - - A',
  // `server/routes/request.ts:745,786`: MANAGE_REQUESTS.
  SeerrAbility.approve: '- - - - - - - - - - - A - - - - A',
  // `server/routes/media.ts:106,172,205`: MANAGE_REQUESTS.
  SeerrAbility.manageMedia: '- - - - - - - - - - - A - - - - A',
  // `request.ts:147-162`: MANAGE_REQUESTS or REQUEST_VIEW.
  SeerrAbility.seeEveryonesRequests: '- - - - - - - - - - A A - - - - A',
  // `request.ts:717-726`: anybody, on their own request that still waits.
  SeerrAbility.cancelOwnPending: 'A A A A A A A A A A A A A A A A A',
  // `server/routes/issue.ts:18-27`: MANAGE_ISSUES, VIEW_ISSUES or
  // CREATE_ISSUES.
  SeerrAbility.viewIssues: '- - - - - - - - - - - - - A A A A',
  // `issue.ts:345`: MANAGE_ISSUES.
  SeerrAbility.manageIssues: '- - - - - - - - - - - - - - - A A',
  // `server/routes/user/index.ts:172,515,553,593`: MANAGE_USERS.
  SeerrAbility.manageUsers: '- - - - - - - - - - - - A - - - A',
  // `server/routes/index.ts:156`: ADMIN, for every `/settings` route.
  SeerrAbility.readSettings: '- - - - - - - - - - - - - - - - A',
};

void main() {
  test('the table covers every ability and every mask', () {
    expect(_table.keys.toSet(), SeerrAbility.values.toSet());
    for (final MapEntry(key: ability, value: row) in _table.entries) {
      expect(row.split(' '), hasLength(_masks.length), reason: '$ability');
    }
  });

  group('an account may what the server lets it', () {
    for (final MapEntry(key: ability, value: row) in _table.entries) {
      test(ability.name, () {
        final cells = row.split(' ');
        for (final (index, (name, mask)) in _masks.indexed) {
          final grant = SeerrGrant.account(permissions: mask);
          final movie = cells[index] == 'M' || cells[index] == 'A';
          final series = cells[index] == 'T' || cells[index] == 'A';
          final where = '${ability.name} with $name';

          expect(
            grant.may(ability, kind: SeerrMediaKind.movie),
            movie,
            reason: '$where, a movie',
          );
          expect(
            grant.may(ability, kind: SeerrMediaKind.tv),
            series,
            reason: '$where, a series',
          );
          // No kind asks "for either".
          expect(grant.may(ability), movie || series, reason: where);
          if (!ability.dependsOnKind) {
            expect(movie, series, reason: '$where does not depend on kind');
          }
        }
      });
    }
  });

  test('the API key is user 1, and may everything', () {
    const key = SeerrGrant.apiKey();
    for (final ability in SeerrAbility.values) {
      for (final kind in [...SeerrMediaKind.values, null]) {
        expect(key.may(ability, kind: kind), isTrue, reason: '$ability $kind');
      }
    }
    expect(key.role, SeerrRole.manager);
    expect(key.isApiKey, isTrue);
  });

  test('ADMIN among other bits still holds everything', () {
    final grant = SeerrGrant.account(
      permissions: _bits([SeerrPermission.admin, SeerrPermission.vote]),
    );
    for (final ability in SeerrAbility.values) {
      expect(grant.may(ability), isTrue, reason: '$ability');
    }
  });

  group('role', () {
    test('a manager is whoever may approve', () {
      for (final (name, mask) in _masks) {
        final grant = SeerrGrant.account(permissions: mask);
        expect(
          grant.role,
          grant.may(SeerrAbility.approve)
              ? SeerrRole.manager
              : SeerrRole.requester,
          reason: name,
        );
      }
      expect(
        SeerrGrant.account(
          permissions: SeerrPermission.manageRequests.value,
        ).role,
        SeerrRole.manager,
      );
      // The household default, `defaultPermissions` (`settings/index.ts:415`).
      expect(
        SeerrGrant.account(permissions: SeerrPermission.request.value).role,
        SeerrRole.requester,
      );
    });

    test('managing users or issues does not make a manager', () {
      for (final permission in [
        SeerrPermission.manageUsers,
        SeerrPermission.manageIssues,
        SeerrPermission.requestView,
        SeerrPermission.requestAdvanced,
      ]) {
        expect(
          SeerrGrant.account(permissions: permission.value).role,
          SeerrRole.requester,
          reason: '$permission',
        );
      }
    });
  });

  group('cancelling one request', () {
    // `request.ts:717-726`: MANAGE_REQUESTS, or the owner while it waits.
    // Anything else is answered 401.
    final rows = <(String, SeerrGrant, bool own, bool waiting, bool may)>[
      ('a requester, own, waiting', _request, true, true, true),
      ('a requester, own, approved', _request, true, false, false),
      ('a requester, not own, waiting', _request, false, true, false),
      ('no permissions, own, waiting', _nothing, true, true, true),
      ('a manager, not own, approved', _manager, false, false, true),
      (
        'the key, not own, approved',
        const SeerrGrant.apiKey(),
        false,
        false,
        true,
      ),
    ];
    for (final (name, grant, own, waiting, may) in rows) {
      test(name, () {
        expect(
          grant.mayCancelRequest(own: own, waitingForApproval: waiting),
          may,
        );
      });
    }
  });

  group('asCapability', () {
    test('the key writes everything', () {
      expect(
        const SeerrGrant.apiKey().asCapability(),
        const CapabilityGrant.readWrite(),
      );
    });

    test('an account writes the abilities it may, by name and by kind', () {
      final grant = SeerrGrant.account(
        permissions: _bits([
          SeerrPermission.requestMovie,
          SeerrPermission.requestView,
        ]),
      ).asCapability();
      expect(grant.writable, {
        'request',
        'request.movie',
        'seeEveryonesRequests',
        'cancelOwnPending',
      });
      expect(
        grant.scopeFor(
          SeerrGrant.resource(SeerrAbility.request, kind: SeerrMediaKind.tv),
        ),
        CapabilityScope.readOnly,
      );
      expect(
        grant.scopeFor(SeerrGrant.resource(SeerrAbility.approve)),
        CapabilityScope.readOnly,
      );
    });

    test('the resource names', () {
      expect(SeerrGrant.resource(SeerrAbility.request), 'request');
      expect(
        SeerrGrant.resource(SeerrAbility.request4k, kind: SeerrMediaKind.tv),
        'request4k.tv',
      );
      // A kind on an ability that does not depend on it is ignored.
      expect(
        SeerrGrant.resource(SeerrAbility.approve, kind: SeerrMediaKind.movie),
        'approve',
      );
    });
  });

  group('from /auth/me', () {
    // `server/routes/auth.ts:33-67`: the whole user, settings trimmed. The
    // email arrives and is personal data.
    final me = <String, dynamic>{
      'id': 7,
      'email': 'sentinel-email@example.com',
      'username': 'sentinel-username',
      'displayName': 'Sentinel Name',
      'userType': 2,
      'permissions': 32,
      'requestCount': 3,
      'warnings': <String>[],
    };

    test('reads the permissions and nothing else', () {
      final grant = SeerrGrant.fromWhoAmI(me);
      expect(grant, SeerrGrant.account(permissions: 32));
      for (final text in [grant.toString(), grant.asCapability().toString()]) {
        expect(text, isNot(contains('sentinel')));
        expect(text, isNot(contains('Sentinel')));
        expect(text, isNot(contains('@')));
      }
    });

    test('an answer without permissions grants nothing', () {
      final grant = SeerrGrant.fromWhoAmI({'id': 7});
      expect(grant.permissions, 0);
      expect(grant.may(SeerrAbility.request), isFalse);
    });
  });

  test('a grant is a value', () {
    expect(
      SeerrGrant.account(permissions: 32),
      SeerrGrant.account(permissions: 32),
    );
    expect(
      SeerrGrant.account(permissions: 32),
      isNot(SeerrGrant.account(permissions: 16)),
    );
    expect(
      const SeerrGrant.apiKey(),
      isNot(SeerrGrant.account(permissions: 2)),
    );
  });

  test('a media kind reads from the wire', () {
    expect(SeerrMediaKind.fromWire('movie'), SeerrMediaKind.movie);
    expect(SeerrMediaKind.fromWire('tv'), SeerrMediaKind.tv);
    expect(SeerrMediaKind.fromWire('music'), isNull);
    expect(SeerrMediaKind.fromWire(null), isNull);
  });
}

final _request = SeerrGrant.account(permissions: SeerrPermission.request.value);
const _nothing = SeerrGrant.account(permissions: 0);
final _manager = SeerrGrant.account(
  permissions: SeerrPermission.manageRequests.value,
);

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_permission.dart';

/// `server/lib/permissions.ts` at Seerr v3.5.0: the `Permission` enum and
/// `hasPermission`. Jellyseerr 2.7.3 differs only in spelling the two
/// blocklist bits *blacklist*; Jellyseerr 1.9.2 lacks them; Overseerr 1.35.0
/// lacks them and MANAGE_SETTINGS.
void main() {
  test('every bit has the value the server uses', () {
    // Copied from `permissions.ts:1-32`, in its order.
    const upstream = {
      SeerrPermission.none: 0,
      SeerrPermission.admin: 2,
      SeerrPermission.manageSettings: 4,
      SeerrPermission.manageUsers: 8,
      SeerrPermission.manageRequests: 16,
      SeerrPermission.request: 32,
      SeerrPermission.vote: 64,
      SeerrPermission.autoApprove: 128,
      SeerrPermission.autoApproveMovie: 256,
      SeerrPermission.autoApproveTv: 512,
      SeerrPermission.request4k: 1024,
      SeerrPermission.request4kMovie: 2048,
      SeerrPermission.request4kTv: 4096,
      SeerrPermission.requestAdvanced: 8192,
      SeerrPermission.requestView: 16384,
      SeerrPermission.autoApprove4k: 32768,
      SeerrPermission.autoApprove4kMovie: 65536,
      SeerrPermission.autoApprove4kTv: 131072,
      SeerrPermission.requestMovie: 262144,
      SeerrPermission.requestTv: 524288,
      SeerrPermission.manageIssues: 1048576,
      SeerrPermission.viewIssues: 2097152,
      SeerrPermission.createIssues: 4194304,
      SeerrPermission.autoRequest: 8388608,
      SeerrPermission.autoRequestMovie: 16777216,
      SeerrPermission.autoRequestTv: 33554432,
      SeerrPermission.recentView: 67108864,
      SeerrPermission.watchlistView: 134217728,
      SeerrPermission.manageBlocklist: 268435456,
      SeerrPermission.viewBlocklist: 1073741824,
    };
    expect({
      for (final permission in SeerrPermission.values)
        permission: permission.value,
    }, upstream);
  });

  test('each bit is one power of two, and 2^29 is never one', () {
    final bits = [
      for (final permission in SeerrPermission.values)
        if (permission != SeerrPermission.none) permission.value,
    ];
    for (final bit in bits) {
      expect(bit & (bit - 1), 0, reason: '$bit is one bit');
    }
    expect(bits.toSet(), hasLength(bits.length));
    expect(bits, isNot(contains(1 << 29)));
    expect(bits, isNot(contains(1)));
  });

  group('a single permission', () {
    // `permissions.ts:47-74`, the non-array branch.
    test('is held by its own bit, and not by a neighbour', () {
      const request = 32;
      expect(hasSeerrPermission(request, SeerrPermission.request), isTrue);
      expect(hasSeerrPermission(request, SeerrPermission.vote), isFalse);
      expect(hasSeerrPermission(0, SeerrPermission.request), isFalse);
    });

    test('ADMIN holds every one', () {
      const admin = 2;
      for (final permission in SeerrPermission.values) {
        expect(
          hasSeerrPermission(admin, permission),
          isTrue,
          reason: '$permission',
        );
      }
    });

    test('NONE is held by everyone, nothing at all included', () {
      // `if (permissions === 0) return true`: before the bits are looked at.
      expect(hasSeerrPermission(0, SeerrPermission.none), isTrue);
    });
  });

  group('a list of permissions', () {
    final requestAndVote =
        SeerrPermission.request.value | SeerrPermission.vote.value;
    const list = [SeerrPermission.request, SeerrPermission.manageRequests];

    test("is read as 'and' by default", () {
      expect(hasSeerrPermissions(requestAndVote, list), isFalse);
      expect(
        hasSeerrPermissions(
          requestAndVote | SeerrPermission.manageRequests.value,
          list,
        ),
        isTrue,
      );
    });

    test("is read as 'or' when asked", () {
      expect(
        hasSeerrPermissions(
          requestAndVote,
          list,
          check: SeerrPermissionCheck.any,
        ),
        isTrue,
      );
      expect(
        hasSeerrPermissions(
          SeerrPermission.vote.value,
          list,
          check: SeerrPermissionCheck.any,
        ),
        isFalse,
      );
    });

    test('ADMIN holds every list, an empty one included', () {
      for (final check in SeerrPermissionCheck.values) {
        expect(hasSeerrPermissions(2, list, check: check), isTrue);
        expect(hasSeerrPermissions(2, const [], check: check), isTrue);
      }
    });

    test('without ADMIN, the edge cases are the server\'s own', () {
      // `[].every(…)` is true and `[].some(…)` false; NONE inside a list is
      // read bit by bit, and `value & 0` is never set.
      expect(hasSeerrPermissions(0, const []), isTrue);
      expect(
        hasSeerrPermissions(0, const [], check: SeerrPermissionCheck.any),
        isFalse,
      );
      expect(hasSeerrPermissions(32, const [SeerrPermission.none]), isFalse);
    });
  });
}

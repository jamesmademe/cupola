import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';

/// `GET /api/v1/user/{id}/quota`: `QuotaResponse` of
/// `server/interfaces/api/userInterfaces.ts`, filled by `User.getQuota`
/// (`server/entity/User.ts:285-389`, Seerr v3.5.0).
void main() {
  test('a reached movie quota and an open series one', () {
    final quota = SeerrQuota.fromJson({
      'movie': {
        'days': 7,
        'limit': 10,
        'used': 10,
        'remaining': 0,
        'restricted': true,
      },
      'tv': {
        'days': 7,
        'limit': 20,
        'used': 4,
        'remaining': 16,
        'restricted': false,
      },
    });
    expect(
      quota.of(SeerrMediaKind.movie),
      const SeerrQuotaStatus(
        days: 7,
        limit: 10,
        used: 10,
        remaining: 0,
        restricted: true,
      ),
    );
    expect(quota.of(SeerrMediaKind.tv).restricted, isFalse);
    expect(quota.of(SeerrMediaKind.tv).remaining, 16);
  });

  test('no limit: a zero limit and no remaining read as none', () {
    // Without a quota, or with MANAGE_USERS, the limit is 0 (or left out) and
    // `remaining` is undefined, so JSON drops it.
    final quota = SeerrQuota.fromJson({
      'movie': {'limit': 0, 'used': 0, 'restricted': false},
      'tv': {'used': 0, 'restricted': false},
    });
    for (final kind in SeerrMediaKind.values) {
      expect(quota.of(kind).limit, isNull, reason: '$kind');
      expect(quota.of(kind).remaining, isNull, reason: '$kind');
      expect(quota.of(kind).days, isNull, reason: '$kind');
      expect(quota.of(kind).restricted, isFalse, reason: '$kind');
    }
    expect(quota, const SeerrQuota());
  });

  test('a missing or malformed answer restricts nothing', () {
    expect(SeerrQuota.fromJson(const {}), const SeerrQuota());
    expect(
      SeerrQuota.fromJson(const {'movie': 'nope', 'tv': null}),
      const SeerrQuota(),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/domain/models/npm_models.dart';

void main() {
  group('NpmProxyHost — the advanced block', () {
    test('an absent block is empty and zero lines, not one blank line', () {
      final host = NpmProxyHost.fromJson({
        'id': 1,
        'domain_names': ['a.example.net'],
        'enabled': true,
      });

      expect(host.advancedConfig, isEmpty);
      expect(host.advancedConfigLines, 0);
    });

    test('the block is counted in lines, for the editor subtitle', () {
      final host = NpmProxyHost.fromJson({
        'id': 1,
        'domain_names': ['a.example.net'],
        'enabled': true,
        'advanced_config':
            'client_max_body_size 50000M;\nproxy_read_timeout 600s;\n',
      });

      expect(host.advancedConfigLines, 2);
    });
  });

  group('NpmCertificate — the only honest renewal reason', () {
    NpmCertificate cert({required String provider, required int inDays}) {
      return NpmCertificate.fromJson({
        'id': 1,
        'provider': provider,
        'nice_name': 'photos.example.net',
        'domain_names': ['photos.example.net'],
        'expires_on': DateTime.utc(
          2026,
          1,
          1,
        ).add(Duration(days: inDays)).toIso8601String(),
      });
    }

    final now = DateTime.utc(2026, 1, 1);

    test('inside certbot\'s own 30-day window, renewal has not run', () {
      expect(
        cert(provider: 'letsencrypt', inDays: 9).renewalNotCompleting(now),
        isTrue,
      );
    });

    test('outside it, nothing is late', () {
      expect(
        cert(provider: 'letsencrypt', inDays: 61).renewalNotCompleting(now),
        isFalse,
      );
    });

    test('an uploaded certificate is never failing to renew', () {
      // Nothing renews it, so nothing can be failing to.
      expect(
        cert(provider: 'other', inDays: 3).renewalNotCompleting(now),
        isFalse,
      );
    });

    test('no expiry date means no claim', () {
      final undated = NpmCertificate.fromJson({
        'id': 2,
        'provider': 'letsencrypt',
        'domain_names': ['x.example.net'],
      });

      expect(undated.renewalNotCompleting(now), isFalse);
      expect(undated.daysUntilExpiry(now), isNull);
    });
  });

  group('NpmCertificate — lapsed is a date, not a day count', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    NpmCertificate cert(Duration offset) => NpmCertificate(
      id: 1,
      provider: 'letsencrypt',
      niceName: 'photos.example.net',
      domainNames: const ['photos.example.net'],
      expiresOn: now.add(offset),
    );

    test('a certificate six hours past its date has expired', () {
      // `daysUntilExpiry` truncates toward zero, so it answers 0 here and a
      // `days < 0` test is blind for a full day. `hasExpired` compares the
      // dates, so it is not.
      final lapsed = cert(const Duration(hours: -6));
      expect(lapsed.daysUntilExpiry(now), 0);
      expect(lapsed.hasExpired(now), isTrue);
    });

    test('one still inside its last day has not', () {
      final due = cert(const Duration(hours: 6));
      expect(due.daysUntilExpiry(now), 0);
      expect(due.hasExpired(now), isFalse);
    });

    test('an undated certificate makes no claim in either direction', () {
      final undated = NpmCertificate.fromJson({
        'id': 2,
        'provider': 'letsencrypt',
        'domain_names': ['x.example.net'],
      });
      expect(undated.hasExpired(now), isFalse);
    });

    test('isExpiringSoon deliberately still covers a lapsed certificate', () {
      // The Dashboard's decision feed is built straight off this predicate, so
      // narrowing it would make an expired certificate disappear from the one
      // surface that collects faults across services. Anything printing the
      // *word* "expiring" pairs it with `hasExpired` instead.
      expect(cert(const Duration(days: -4)).isExpiringSoon(now), isTrue);
    });
  });

  group('NpmAccount — decision 34', () {
    NpmAccount account(Map<String, dynamic> json) => NpmAccount.fromJson(json);

    test('an admin short-circuits the permission map it never gets', () {
      final admin = account({
        'id': 1,
        'nickname': 'Admin',
        'roles': ['admin'],
      });

      expect(admin.isAdmin, isTrue);
      expect(admin.isViewOnly, isFalse);
      expect(admin.canManage(NpmResource.accessLists), isTrue);
    });

    test('view means read, manage means write', () {
      final user = account({
        'id': 2,
        'nickname': 'Reader',
        'roles': ['user'],
        'permissions': {'proxy_hosts': 'view', 'access_lists': 'manage'},
      });

      expect(user.canManage(NpmResource.proxyHosts), isFalse);
      expect(user.canManage(NpmResource.accessLists), isTrue);
      // One manageable resource is enough to stop the banner: this account is
      // not view-only, it is scoped.
      expect(user.isViewOnly, isFalse);
    });

    test('an account with no manage anywhere is view-only', () {
      final user = account({
        'id': 3,
        'roles': ['user'],
        'permissions': {'proxy_hosts': 'view', 'certificates': 'hidden'},
      });

      expect(user.isViewOnly, isTrue);
    });

    test('the email is never modelled', () {
      // The role is what the UI needs; the address identifies a person and
      // would ride along into every diagnostics dump that touched this object.
      final user = account({
        'id': 4,
        'email': 'matt@example.com',
        'nickname': 'Matt',
        'roles': ['user'],
      });

      expect(user.name, 'Matt');
      expect(user.toString(), isNot(contains('matt@example.com')));
    });
  });
}

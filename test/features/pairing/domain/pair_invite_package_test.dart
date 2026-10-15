/// The package of an invite shown in person: one Seerr, what its addresses
/// ask for and their pins, never the key or an account; and, read back, a
/// package that says it is an invite and holds anything more is refused.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/pair_fixtures.dart';

void main() {
  Map<String, Object?> json() =>
      jsonDecode(jsonEncode(pairFixtureInvitePackage().toJson()))
          as Map<String, Object?>;
  PairPackage read(Map<String, Object?> j) =>
      PairPackage.decode(gzip.encode(utf8.encode(jsonEncode(j))));

  group('what an invite carries', () {
    test('one Seerr at its two addresses, with what the address away asks '
        'for', () {
      final package = pairFixtureInvitePackage();
      expect(package.invite, isTrue);
      final seerr = package.connections.single;
      expect(seerr.service, ServiceKey.seerr);
      expect(seerr.url, 'http://192.168.1.10:5055');
      expect(seerr.away!.url, 'https://seerr.example.net');
      expect(
        seerr.away!.access,
        const CloudflareServiceToken(
          clientId: 'fixture-id',
          clientSecret: 'fixture-secret',
        ),
      );
    });

    test('never the key, an account or another service', () {
      final text = jsonEncode(pairFixtureInvitePackage().toJson());
      expect(text, isNot(contains('seerr-fixture-key')));
      expect(text, isNot(contains('credential')));
      expect(text, isNot(contains('account')));
      expect(pairFixtureInvitePackage().connections, hasLength(1));
    });

    test('only the pins of its own addresses', () {
      expect(pairFixtureInvitePackage().certificates, {
        'https://seerr.example.net:443': pairFixturePin,
      });
    });

    test('prints that it is one, and counts', () {
      expect(
        pairFixtureInvitePackage().toString(),
        'PairPackage(invite, from iphone, 1 connections, 1 certificates)',
      );
    });
  });

  group('reading an invite', () {
    test('round-trips, and reads back as the invite it was made from', () {
      final back = read(json());
      expect(back.invite, isTrue);
      final invite = back.asInvite()!;
      expect(invite.home, 'http://192.168.1.10:5055');
      expect(invite.away, 'https://seerr.example.net');
      expect(invite.homePin, isNull);
      expect(invite.awayPin, pairFixturePin);
      expect(invite.homeAccess, const NoAccess());
      expect(
        invite.awayAccess,
        const CloudflareServiceToken(
          clientId: 'fixture-id',
          clientSecret: 'fixture-secret',
        ),
      );
    });

    test('a package of everything is no invite', () {
      expect(pairFixturePackage().invite, isFalse);
      expect(pairFixturePackage().asInvite(), isNull);
      expect(pairFixturePackage().toJson(), isNot(contains('invite')));
    });

    test('refuses an invite that holds anything an invite never does', () {
      Map<String, Object?> seerr(Map<String, Object?> j) =>
          (j['connections']! as List).first as Map<String, Object?>;
      final cases = <String, void Function(Map<String, Object?>)>{
        'a key': (j) => seerr(j)['credential'] = 'k',
        'an account': (j) => seerr(j)['account'] = {
          'kind': 'local',
          'userId': 4,
          'permissions': 0,
        },
        'a second connection': (j) => (j['connections']! as List).add({
          'service': 'radarr',
          'url': 'http://192.168.1.10:7878',
          'credential': 'k',
        }),
        'another service': (j) => seerr(j)['service'] = 'radarr',
        'a pin of another address': (j) =>
            (j['certificates']! as Map)['https://radarr.home.arpa:443'] =
                pairFixturePin,
        'a mark that is not a yes or no': (j) => j['invite'] = 'yes',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final j = json();
        value(j);
        expect(() => read(j), throwsFormatException, reason: key);
      }
    });
  });
}

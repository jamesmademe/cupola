import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _radarrPin =
    'aa00000000000000000000000000000000000000000000000000000000000001';
const _awayPin =
    'bb00000000000000000000000000000000000000000000000000000000000002';
const _strayPin =
    'cc00000000000000000000000000000000000000000000000000000000000003';

/// A sending device: a Radarr pinned, a Seerr signed in with an account and
/// reached away through Cloudflare, a qBittorrent with a password, a Sonarr
/// whose key the keychain kept, and a slot left blank.
SettingsModel _sender() => const SettingsModel(
  plexClientId: 'install-of-the-sender',
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://radarr.home.arpa',
      credential: 'radarr-key',
    ),
    ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'http://192.168.1.10:5055',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.jellyfin,
        login: 'anna',
        userId: 4,
        displayName: 'Anna',
        session: 'seerr-session',
        permissions: 32,
      ),
      away: ConnectionAddress(
        url: 'https://seerr.example.net',
        access: CloudflareServiceToken(
          clientId: 'cf-id',
          clientSecret: 'cf-secret',
        ),
      ),
    ),
    ServiceInstance(
      id: 'qbittorrent',
      service: ServiceKey.qbittorrent,
      url: 'http://192.168.1.10:8080',
      username: 'admin',
      credential: 'qb-password',
    ),
    ServiceInstance(
      id: 'sonarr',
      service: ServiceKey.sonarr,
      url: 'http://192.168.1.10:8989',
      unreadSecret: UnreadSecret.credential,
    ),
    ServiceInstance(id: 'lidarr', service: ServiceKey.lidarr),
  ],
  trustedCertificates: {
    'https://radarr.home.arpa:443': _radarrPin,
    'https://seerr.example.net:443': _awayPin,
    'https://old.example.net:443': _strayPin,
  },
);

PairPackage _package() =>
    PairPackage.everything(_sender(), from: PairDevice.iphone);

void main() {
  group('what travels', () {
    test('every connection with an address, in order', () {
      expect(
        [for (final c in _package().connections) c.service],
        [
          ServiceKey.radarr,
          ServiceKey.seerr,
          ServiceKey.qbittorrent,
          ServiceKey.sonarr,
        ],
      );
    });

    test('the secrets, but never a Seerr session', () {
      final [radarr, seerr, qb, sonarr] = _package().connections;
      expect(radarr.credential, 'radarr-key');
      expect(qb.credential, 'qb-password');
      expect(seerr.away!.access, isA<CloudflareServiceToken>());
      expect(seerr.account!.isSignedIn, isFalse);
      expect(seerr.account!.displayName, 'Anna');
      expect(sonarr.unreadSecret, UnreadSecret.credential);
    });

    test('the pins of their origins only', () {
      expect(_package().certificates, {
        'https://radarr.home.arpa:443': _radarrPin,
        'https://seerr.example.net:443': _awayPin,
      });
    });

    test("never Cupola's Plex identity", () {
      final json = jsonEncode(_package().toJson());
      expect(json, isNot(contains('install-of-the-sender')));
      expect(json, isNot(contains('seerr-session')));
    });

    test('prints counts, never a value', () {
      final text = _package().toString();
      expect(text, 'PairPackage(from iphone, 4 connections, 2 certificates)');
    });
  });

  group('reading a package', () {
    test('round-trips through its bytes', () {
      final package = _package();
      expect(PairPackage.decode(package.encode()).toJson(), package.toJson());
    });

    Map<String, Object?> json() =>
        jsonDecode(jsonEncode(_package().toJson())) as Map<String, Object?>;
    PairPackage read(Map<String, Object?> json) =>
        PairPackage.decode(gzip.encode(utf8.encode(jsonEncode(json))));

    test('says a later version is one', () {
      expect(() => read(json()..['v'] = 2), throwsA(isA<PairPackageNewer>()));
    });

    test('leaves out a service this build does not know, and counts it', () {
      final changed = json();
      (changed['connections']! as List).add({
        'service': 'jellyseerr-next',
        'url': 'http://nas:1',
      });
      final package = read(changed);
      expect(package.connections, hasLength(4));
      expect(package.unknown, 1);
    });

    test('refuses what the sending device never writes', () {
      final cases = <String, void Function(Map<String, Object?>)>{
        'an address that is not one': (j) =>
            ((j['connections']! as List).first as Map)['url'] = 'ftp://nas',
        'a pin that is not a fingerprint': (j) =>
            (j['certificates']! as Map)['https://radarr.home.arpa:443'] = 'x',
        'a pin under a raw address': (j) =>
            (j['certificates']! as Map)['radarr.home.arpa'] = _radarrPin,
        'a key beside an account': (j) =>
            ((j['connections']! as List)[1] as Map)['credential'] = 'k',
        'an access of no kind': (j) =>
            ((j['connections']! as List)[1] as Map)['away'] = {
              'url': 'https://seerr.example.net',
              'access': {'kind': 'mystery'},
            },
        'a sender of no kind': (j) => j['from'] = 'toaster',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => read(json()..also(value)),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('refuses bytes that are not a package', () {
      expect(() => PairPackage.decode([1, 2, 3]), throwsFormatException);
      expect(
        () => PairPackage.decode(gzip.encode(utf8.encode('[]'))),
        throwsFormatException,
      );
    });

    test('stops unpacking past its cap', () {
      final huge = gzip.encode(Uint8List(PairPackage.maxBytes + 1));
      expect(huge.length, lessThan(10000));
      expect(() => PairPackage.decode(huge), throwsFormatException);
    });
  });

  group('the device it comes from', () {
    test('is named by kind', () {
      expect(
        PairDevice.of(TargetPlatform.iOS, tablet: false).phrase,
        'your iPhone',
      );
      expect(
        PairDevice.of(TargetPlatform.iOS, tablet: true).phrase,
        'your iPad',
      );
      expect(
        PairDevice.of(TargetPlatform.macOS, tablet: false).phrase,
        'your Mac',
      );
      expect(
        PairDevice.of(TargetPlatform.android, tablet: false).phrase,
        'your Android phone',
      );
    });
  });

  group('copying it in', () {
    final random = Random(7);

    test('onto an empty device adds everything, with the first ids', () {
      final plan = PairPlan.of(
        _package(),
        const SettingsModel(),
        random: random,
      );
      expect(
        [for (final c in plan.toAdd) c.id],
        ['radarr', 'seerr', 'qbittorrent', 'sonarr'],
      );
      expect(plan.alreadyHere, isEmpty);
      expect(plan.certificates, hasLength(2));
      expect(plan.signInAgain.single.service, ServiceKey.seerr);
      expect(plan.sentWithout(plan.toAdd.last), UnreadSecret.credential);
      expect(plan.toAdd.last.unreadSecret, isNull);
      expect(plan.sentWithout(plan.toAdd.first), isNull);
    });

    test('leaves a server already here as it is', () {
      const here = SettingsModel(
        instances: [
          ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            url: 'https://radarr.home.arpa/',
            credential: 'my-own-key',
          ),
          ServiceInstance(
            id: 'seerr',
            service: ServiceKey.seerr,
            url: 'https://seerr.example.net',
            credential: 'seerr-key',
          ),
        ],
      );
      final plan = PairPlan.of(_package(), here, random: random);
      expect(
        [for (final c in plan.alreadyHere) c.service],
        [ServiceKey.radarr, ServiceKey.seerr],
      );
      expect(
        [for (final c in plan.toAdd) c.service],
        [ServiceKey.qbittorrent, ServiceKey.sonarr],
      );
      final after = plan.applyTo(here);
      expect(after.instanceById('radarr')!.credential, 'my-own-key');
      expect(after.instances.take(2), here.instances);
    });

    test('labels a second connection of a service from its address', () {
      const here = SettingsModel(
        instances: [
          ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            url: 'http://192.168.1.30:7878',
            credential: 'k',
          ),
        ],
      );
      final added = PairPlan.of(_package(), here, random: random).toAdd.first;
      expect(added.service, ServiceKey.radarr);
      expect(added.id, startsWith('radarr-'));
      expect(added.label, 'radarr');
    });

    test('numbers a label already taken', () {
      const here = SettingsModel(
        instances: [
          ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            label: 'radarr',
            url: 'http://192.168.1.30:7878',
            credential: 'k',
          ),
        ],
      );
      final added = PairPlan.of(_package(), here, random: random).toAdd.first;
      expect(added.label, 'radarr 2');
    });

    test('never replaces a pin this device holds', () {
      const mine =
          'dd00000000000000000000000000000000000000000000000000000000000004';
      const here = SettingsModel(
        trustedCertificates: {'https://radarr.home.arpa:443': mine},
      );
      final plan = PairPlan.of(_package(), here, random: random);
      expect(plan.certificates.keys, ['https://seerr.example.net:443']);
      expect(
        plan.applyTo(here).trustedCertificates['https://radarr.home.arpa:443'],
        mine,
      );
    });

    test('a second copy adds nothing', () {
      final once = PairPlan.of(
        _package(),
        const SettingsModel(),
        random: random,
      ).applyTo(const SettingsModel());
      final again = PairPlan.of(_package(), once, random: random);
      expect(again.toAdd, isEmpty);
      expect(again.alreadyHere, hasLength(4));
      expect(again.addsAnything, isFalse);
    });
  });
}

extension<T> on T {
  T also(void Function(T) change) {
    change(this);
    return this;
  }
}

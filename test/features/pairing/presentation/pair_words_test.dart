/// What the two pairing screens say, said once: counts, titles, the word each
/// service calls its secret, and the words and tone of every way a copy can
/// fail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/pairing/presentation/pair_words.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/pair_fixtures.dart';

ServiceInstance _connection(
  ServiceKey service, {
  String label = '',
  String url = 'http://192.168.1.10:7878',
  String credential = 'key',
  UnreadSecret? unread,
}) => ServiceInstance(
  id: '${service.name}-$label',
  service: service,
  label: label,
  url: url,
  credential: credential,
  unreadSecret: unread,
);

void main() {
  group('counts', () {
    test('a service, and services', () {
      expect(pairServices(1), '1 service');
      expect(pairServices(14), '14 services');
    });

    test('a trusted certificate, and trusted certificates', () {
      expect(pairCertificates(1), '1 trusted certificate');
      expect(pairCertificates(3), '3 trusted certificates');
    });

    test('services and their keys', () {
      expect(pairServicesAndKeys(1), '1 service and its key');
      expect(pairServicesAndKeys(12), '12 services and their keys');
    });
  });

  group('the titles the sending screen names', () {
    test('four or fewer are joined with commas and an and', () {
      expect(pairNamedList(const []), '');
      expect(pairNamedList(const ['Radarr']), 'Radarr');
      expect(pairNamedList(const ['Radarr', 'Sonarr']), 'Radarr and Sonarr');
      expect(
        pairNamedList(const ['Radarr', 'Sonarr', 'Seerr']),
        'Radarr, Sonarr and Seerr',
      );
      expect(
        pairNamedList(const ['Radarr', 'Sonarr', 'Seerr', 'Jellyfin']),
        'Radarr, Sonarr, Seerr and Jellyfin',
      );
    });

    test('past four, the first four and the rest counted', () {
      final names = [
        'Radarr',
        'Sonarr',
        'Seerr',
        'Jellyfin',
        for (var i = 0; i < 8; i++) 'More $i',
      ];
      expect(
        pairNamedList(names),
        'Radarr, Sonarr, Seerr, Jellyfin and 8 more',
      );
      expect(
        pairNamedList(names.take(5).toList()),
        'Radarr, Sonarr, Seerr, Jellyfin and 1 more',
      );
    });
  });

  group('the word for a secret', () {
    test('is the registry\'s: key, token, or password for a sign-in', () {
      expect(pairSecretWord(ServiceKey.radarr), 'key');
      expect(pairSecretWord(ServiceKey.seerr), 'key');
      expect(pairSecretWord(ServiceKey.plex), 'token');
      expect(pairSecretWord(ServiceKey.qbittorrent), 'password');
      expect(pairSecretWord(ServiceKey.nginxProxyManager), 'password');
    });

    test('of a connection: its secret, or its access', () {
      final radarr = _connection(ServiceKey.radarr);
      expect(pairSecretNamed(radarr, UnreadSecret.credential), 'key');
      expect(pairSecretNamed(radarr, UnreadSecret.access), 'access');
    });

    test('a labelled connection is named by service and label', () {
      expect(pairSubject(_connection(ServiceKey.radarr)), 'Radarr');
      expect(
        pairSubject(_connection(ServiceKey.radarr, label: '4K')),
        'Radarr 4K',
      );
    });
  });

  group('the countdown', () {
    test('reads minutes and seconds', () {
      expect(pairCountdown(const Duration(minutes: 2)), 'Closes in 2:00');
      expect(
        pairCountdown(const Duration(minutes: 1, seconds: 52)),
        'Closes in 1:52',
      );
      expect(pairCountdown(const Duration(seconds: 9)), 'Closes in 0:09');
    });

    test('rounds down to the second, and never goes below zero', () {
      expect(
        pairCountdown(const Duration(seconds: 3, milliseconds: 900)),
        'Closes in 0:03',
      );
      expect(pairCountdown(Duration.zero), 'Closes in 0:00');
      expect(pairCountdown(const Duration(seconds: -4)), 'Closes in 0:00');
    });
  });

  group('what moves', () {
    test('lists the keys, the certificates, the account that signs in again, '
        'what stays behind, and the network, in that order', () {
      final moves = pairMovesOf(pairFixturePackage());
      expect(
        [for (final m in moves) (m.icon, m.title, m.detail)],
        [
          (
            Icons.key_rounded,
            '4 services and their keys',
            'Radarr, Sonarr, Seerr and qBittorrent',
          ),
          (
            Icons.verified_user_outlined,
            '1 trusted certificate',
            'So the new phone trusts the same servers you already trusted',
          ),
          (
            Icons.person_outline_rounded,
            'Seerr signs in again on the new phone',
            'A sign-in stays on the device it was made on',
          ),
          (
            Icons.key_off_rounded,
            "qBittorrent's password stays behind",
            "This device could not read it. Paste it on the new phone.",
          ),
          (
            Icons.wifi_rounded,
            'Encrypted, over your home network only',
            'Both phones need to be on your Wi-Fi',
          ),
        ],
      );
    });

    test('leaves out what does not apply, and says one service in the '
        'singular', () {
      final moves = pairMovesOf(
        PairPackage(
          from: PairDevice.mac,
          connections: [_connection(ServiceKey.radarr)],
        ),
      );
      expect(
        [for (final m in moves) m.title],
        ['1 service and its key', 'Encrypted, over your home network only'],
      );
      expect(moves.first.detail, 'Radarr');
    });

    test('says an access left behind, one row for each connection', () {
      final moves = pairMovesOf(
        PairPackage(
          from: PairDevice.mac,
          connections: [
            _connection(ServiceKey.radarr, unread: UnreadSecret.access),
            _connection(
              ServiceKey.radarr,
              label: '4K',
              unread: UnreadSecret.credential,
            ),
            _connection(ServiceKey.plex, unread: UnreadSecret.credential),
          ],
        ),
      );
      expect(
        [for (final m in moves) m.title],
        [
          '3 services and their keys',
          "Radarr's access stays behind",
          "Radarr 4K's key stays behind",
          "Plex's token stays behind",
          'Encrypted, over your home network only',
        ],
      );
    });

    test('names a labelled connection beside its sibling', () {
      final moves = pairMovesOf(
        PairPackage(
          from: PairDevice.mac,
          connections: [
            _connection(ServiceKey.radarr),
            _connection(ServiceKey.radarr, label: '4K'),
          ],
        ),
      );
      expect(moves.first.detail, 'Radarr and Radarr 4K');
    });

    test('carries counts and titles, never an address, a key or a secret', () {
      final said = [
        for (final m in pairMovesOf(pairFixturePackage()))
          '${m.title} ${m.detail}',
      ].join(' ');
      for (final secret in [
        'radarr-fixture-key',
        'sonarr-fixture-key',
        'seerr-fixture-session',
        'fixture-secret',
        '192.168.1.10',
        'radarr.home.arpa',
        pairFixturePin,
      ]) {
        expect(said, isNot(contains(secret)));
      }
    });
  });

  group('why a code closed', () {
    test('says each end in words', () {
      expect(
        pairClosedBecause(PairServerEnd.expired),
        'Its two minutes are up.',
      );
      expect(
        pairClosedBecause(PairServerEnd.closed),
        "It can't be used any more.",
      );
      expect(
        pairClosedBecause(PairServerEnd.refused),
        'Something on your network asked for the wrong thing three times.',
      );
    });
  });

  group('when nothing arrived', () {
    test('every failure has a tone, words and a remedy of its own', () {
      expect(
        {
          for (final f in PairReceiveFailure.values)
            f: (
              f.notice.tone,
              f.notice.headline,
              f.notice.sentence,
              f.notice.fillsStartAgain,
            ),
        },
        {
          PairReceiveFailure.unreachable: (
            StatusTone.error,
            "Cupola could not reach the other device",
            'Both need to be on the same Wi-Fi.',
            false,
          ),
          PairReceiveFailure.expired: (
            StatusTone.info,
            'This code has expired',
            'Make a new code on the other device.',
            false,
          ),
          PairReceiveFailure.unreadable: (
            StatusTone.warning,
            "Cupola could not read what the other device sent",
            'Make a new code on the other device.',
            true,
          ),
          PairReceiveFailure.newer: (
            StatusTone.warning,
            'This came from a newer Cupola',
            'Update Cupola on this device, then make a new code.',
            true,
          ),
          PairReceiveFailure.notWhole: (
            StatusTone.warning,
            "This link isn't whole",
            'Copy it again, or make a new code on the other device.',
            true,
          ),
        },
      );
    });

    test('red is only the device that did not answer, and a fill is only an '
        'amber fault\'s', () {
      for (final f in PairReceiveFailure.values) {
        final notice = f.notice;
        expect(
          notice.tone == StatusTone.error,
          f == PairReceiveFailure.unreachable,
          reason: f.name,
        );
        expect(
          notice.fillsStartAgain,
          notice.tone == StatusTone.warning,
          reason: f.name,
        );
      }
    });
  });

  group('what the copy would do', () {
    test('counts what is new, and what is here already', () {
      final plan = pairFixturePlan(
        settings: const SettingsModel(
          instances: [
            ServiceInstance(
              id: 'mine',
              service: ServiceKey.sonarr,
              url: 'http://192.168.1.10:8989',
              credential: 'mine',
            ),
          ],
        ),
      );
      expect(
        pairPlanCounts(plan),
        '3 services · 1 trusted certificate · 1 already here',
      );
      expect(pairAddLabel(plan), 'Add 3 services');
    });

    test('leaves out a count of nothing', () {
      final plan = PairPlan.of(
        PairPackage(
          from: PairDevice.iphone,
          connections: [_connection(ServiceKey.radarr)],
        ),
        const SettingsModel(),
      );
      expect(pairPlanCounts(plan), '1 service');
      expect(pairAddLabel(plan), 'Add 1 service');
    });

    test('with only certificates new, adds those', () {
      final package = PairPackage(
        from: PairDevice.iphone,
        connections: [
          _connection(ServiceKey.radarr, url: 'https://radarr.home.arpa'),
        ],
        certificates: const {'https://radarr.home.arpa:443': pairFixturePin},
      );
      final plan = PairPlan.of(
        package,
        SettingsModel(
          instances: [
            _connection(ServiceKey.radarr, url: 'https://radarr.home.arpa'),
          ],
        ),
      );
      expect(plan.toAdd, isEmpty);
      expect(pairAddLabel(plan), 'Add 1 trusted certificate');
    });

    test('notes only what applies, one for each secret that stayed behind', () {
      final plan = PairPlan.of(
        PairPackage(
          from: PairDevice.iphone,
          connections: [
            _connection(ServiceKey.radarr, unread: UnreadSecret.access),
            _connection(
              ServiceKey.sonarr,
              url: 'http://192.168.1.10:8989',
              unread: UnreadSecret.credential,
            ),
          ],
          unknown: 2,
        ),
        const SettingsModel(),
      );
      expect(pairPlanNotes(plan), [
        "Radarr arrives without its access. Paste it here once it's added.",
        "Sonarr arrives without its key. Paste it here once it's added.",
        "2 services this version of Cupola doesn't know stay behind.",
      ]);
    });

    test('a Seerr account signs in again, said once', () {
      final plan = pairFixturePlan();
      expect(pairPlanNotes(plan).first, startsWith('Sign in to Seerr again'));
      expect(
        pairPlanNotes(plan).where((n) => n.startsWith('Sign in')),
        hasLength(1),
      );
    });
  });

  group('offering the code', () {
    test('only with a connection to hand over', () {
      expect(offersAnotherDevice(const SettingsModel()), isFalse);
      expect(offersAnotherDevice(pairFixtureSender()), isTrue);
    });

    test('a signed-out Seerr account is a connection', () {
      expect(
        offersAnotherDevice(
          const SettingsModel(
            instances: [
              ServiceInstance(
                id: 'seerr',
                service: ServiceKey.seerr,
                url: 'http://192.168.1.10:5055',
                account: SeerrAccountSignIn(
                  kind: SeerrAccountKind.local,
                  login: 'anna@example.com',
                ),
              ),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('an address with no key or account is not', () {
      expect(
        offersAnotherDevice(
          const SettingsModel(
            instances: [
              ServiceInstance(
                id: 'seerr',
                service: ServiceKey.seerr,
                url: 'http://192.168.1.10:5055',
              ),
            ],
          ),
        ),
        isFalse,
      );
    });
  });
}

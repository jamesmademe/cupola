import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _homePin =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _awayPin =
    '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

ServiceInstance _seerr({
  String url = 'https://nas.home.arpa:5055',
  ConnectionAccess access = const NoAccess(),
  ConnectionAddress? away = const ConnectionAddress(
    url: 'https://seerr.example.net',
  ),
}) => ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: url,
  credential: 'sentinel-api-key',
  access: access,
  away: away,
);

SettingsModel _trusting(List<(String, String)> pins) {
  var settings = const SettingsModel();
  for (final (url, pin) in pins) {
    settings = settings.copyWithTrustedCertificate(url: url, fingerprint: pin);
  }
  return settings;
}

void main() {
  group('an invite made from the operator\'s connection', () {
    test('carries both addresses, the pin of each, and the title', () {
      final invite = SeerrInvite.of(
        _seerr(),
        _trusting([
          ('https://nas.home.arpa:5055', _homePin),
          ('https://seerr.example.net', _awayPin),
        ]),
        title: 'Rossi Movies',
      );

      expect(invite.home, 'https://nas.home.arpa:5055');
      expect(invite.away, 'https://seerr.example.net');
      expect(invite.homePin, _homePin);
      expect(invite.awayPin, _awayPin);
      expect(invite.title, 'Rossi Movies');
    });

    test('never carries a key, a session or a gateway\'s access', () {
      final withKey = _seerr(
        access: const CloudflareServiceToken(
          clientId: 'sentinel-home-id',
          clientSecret: 'sentinel-home-secret',
        ),
        away: const ConnectionAddress(
          url: 'https://seerr.example.net',
          access: ProxyPassword(
            username: 'sentinel-user',
            password: 'sentinel-password',
          ),
        ),
      );
      const withSession = ServiceInstance(
        id: 'seerr-2',
        service: ServiceKey.seerr,
        url: 'http://192.168.1.10:5055',
        account: SeerrAccountSignIn(
          kind: SeerrAccountKind.local,
          login: 'sentinel-login@example.com',
          userId: 7,
          session: 'sentinel-session',
        ),
      );

      for (final connection in [withKey, withSession]) {
        final link = SeerrInvite.of(connection, const SettingsModel()).toLink();
        expect(link, isNot(contains('sentinel')));
        expect(link, startsWith('cupola://invite?v=1&home='));
      }
    });

    test('leaves out an address away behind a gateway, and says so', () {
      final connection = _seerr(
        away: const ConnectionAddress(
          url: 'https://seerr.example.net',
          access: CloudflareServiceToken(clientId: 'id', clientSecret: 'x'),
        ),
      );

      expect(SeerrInvite.of(connection, const SettingsModel()).away, isNull);
      expect(inviteLimitsOf(connection), [SeerrInviteLimit.awayBehindGateway]);
    });

    test('a server with one address works at home, and says so', () {
      final connection = _seerr(away: null);

      expect(SeerrInvite.of(connection, const SettingsModel()).away, isNull);
      expect(inviteLimitsOf(connection), [SeerrInviteLimit.homeOnly]);
      expect(inviteLimitsOf(_seerr()), isEmpty);
    });

    test('an http address carries no pin', () {
      final invite = SeerrInvite.of(
        _seerr(url: 'http://192.168.1.10:5055'),
        _trusting([('https://seerr.example.net', _awayPin)]),
      );

      expect(invite.homePin, isNull);
      expect(invite.awayPin, _awayPin);
    });

    test('a long or broken title is cut and cleaned', () {
      final invite = SeerrInvite.of(
        _seerr(),
        const SettingsModel(),
        title: 'Movies\nat home ${'x' * 80}',
      );

      expect(invite.title, startsWith('Movies at home'));
      expect(invite.title!.length, SeerrInvite.titleLength);
    });
  });

  group('reading an invite', () {
    final invite = SeerrInvite(
      home: 'https://nas.home.arpa:5055',
      away: 'https://seerr.example.net',
      homePin: _homePin,
      awayPin: _awayPin,
      title: 'Rossi & Co. Movies',
    );

    test('reads back what was written', () {
      expect(SeerrInvite.tryParse(invite.toLink()), invite);
      expect(SeerrInvite.fromQuery(invite.toUri().queryParameters), invite);
    });

    test('the addresses are encoded, so a chat links nothing inside', () {
      expect(invite.toLink(), isNot(contains('https://nas')));
    });

    test('finds the link inside a pasted message', () {
      expect(
        SeerrInvite.tryParse('Here you go:\n${invite.toLink()}\nsee you'),
        invite,
      );
      expect(SeerrInvite.mentionsInvite('nas.home.arpa:5055'), isFalse);
    });

    test('refuses a link that is not whole or not of this version', () {
      final query = invite.toUri().queryParameters;
      for (final broken in [
        {...query, 'v': '2'},
        {...query}..remove('v'),
        {...query}..remove('home'),
        {...query, 'home': 'nas.home.arpa:5055'},
        {...query, 'home': 'ftp://nas.home.arpa'},
        {...query, 'away': 'not an address'},
        {...query, 'homePin': 'AB:CD'},
        {...query, 'awayPin': _awayPin.toUpperCase()},
      ]) {
        expect(SeerrInvite.fromQuery(broken), isNull, reason: '$broken');
      }
      expect(SeerrInvite.tryParse('cupola://invite?v=1'), isNull);
      expect(
        SeerrInvite.mentionsInvite('cupola://invite?v=1'),
        isTrue,
        reason: 'a broken invite is still one, and is said so',
      );
    });

    test('a pin for an http address is not kept', () {
      final read = SeerrInvite.fromQuery({
        'v': '1',
        'home': 'http://192.168.1.10:5055',
        'homePin': _homePin,
      });

      expect(read, isNotNull);
      expect(read!.homePin, isNull);
    });

    test('vouches for a pin only at its own origin', () {
      expect(invite.pinFor('https://nas.home.arpa:5055/api/v1'), _homePin);
      expect(invite.pinFor('https://seerr.example.net'), _awayPin);
      expect(invite.pinFor('https://nas.home.arpa:443'), isNull);
      expect(invite.pinFor('https://elsewhere.example.net'), isNull);
    });

    test('draws up a connection with its two addresses and nothing else', () {
      final draft = invite.draft('seerr');

      expect(draft.service, ServiceKey.seerr);
      expect(draft.url, invite.home);
      expect(draft.away?.url, invite.away);
      expect(draft.credential, isEmpty);
      expect(draft.account, isNull);
    });

    test('the app is opened with the whole link or with its path', () {
      expect(SeerrInvite.isInviteUri(invite.toUri()), isTrue);
      expect(SeerrInvite.isInviteUri(Uri.parse('/invite?v=1')), isTrue);
      expect(SeerrInvite.isInviteUri(Uri.parse('/welcome')), isFalse);
      expect(
        SeerrInvite.isInviteUri(Uri.parse('https://invite.example.com/')),
        isFalse,
      );
    });
  });
}

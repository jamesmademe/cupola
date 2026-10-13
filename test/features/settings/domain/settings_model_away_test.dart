/// A connection's two addresses are two origins: a certificate trusted for
/// either is that connection's, and so is the access each one sends.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _token = CloudflareServiceToken(
  clientId: 'id.access',
  clientSecret: 'sentinel-secret',
);

const _homePin = 'aa11';
const _awayPin = 'bb22';

/// Radarr at home on the NAS, away through a tunnel behind Cloudflare
/// Access; Sonarr at home only, on the same NAS.
const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'https://nas.lan:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(url: 'https://radarr.example.com', access: _token),
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://nas.lan:8989',
  credential: 'sonarr-key',
);

SettingsModel get _settings =>
    const SettingsModel(instances: [_radarr, _sonarr])
        .copyWithTrustedCertificate(url: _radarr.url, fingerprint: _homePin)
        .copyWithTrustedCertificate(
          url: _radarr.away!.url,
          fingerprint: _awayPin,
        );

void main() {
  group('trust is per origin, and both addresses are origins', () {
    test('the origin a connection is reached at away from home counts it', () {
      expect(
        _settings.instancesSharingOriginOf('https://radarr.example.com/x'),
        [_radarr],
      );
      expect(_settings.servicesSharingOriginOf('https://radarr.example.com'), [
        ServiceKey.radarr,
      ]);
    });

    test('an origin used only away from home is not forgotten when another '
        'connection leaves it', () {
      // Sonarr was saved at the tunnel's address and moves back to the NAS:
      // Radarr still goes there away from home, and the certificate stays.
      const tunnel = 'https://radarr.example.com/sonarr';
      final settings = _settings
          .copyWithInstance(_sonarr.copyWith(url: tunnel))
          .copyWithInstance(_sonarr)
          .copyWithoutUnusedCertificate(tunnel);

      expect(settings.pinForUrl('https://radarr.example.com'), _awayPin);
    });

    test('an address at home that moves keeps the pin its address away '
        'still uses, and forgets its own', () {
      final moved = _settings.copyWithInstance(
        _radarr.copyWith(url: 'https://radarr.lan:7878'),
      );
      final settings = moved.copyWithoutUnusedCertificate(_radarr.url);

      expect(settings.pinForUrl(_radarr.url), isNull);
      expect(settings.pinForUrl(_radarr.away!.url), _awayPin);
    });

    test('removing a connection forgets both of its origins when nothing '
        'else uses them', () {
      final settings = _settings
          .copyWithoutInstance('radarr')
          .copyWithoutUnusedCertificatesOf(_radarr);

      expect(settings.trustedCertificates, isEmpty);
    });

    test('removing a connection keeps an origin another connection reaches '
        'away from home', () {
      // Sonarr is reached away through the same tunnel as Radarr.
      final settings = _settings
          .copyWithInstance(
            _sonarr.copyWith(
              away: const ConnectionAddress(
                url: 'https://radarr.example.com/sonarr',
              ),
            ),
          )
          .copyWithoutInstance('radarr')
          .copyWithoutUnusedCertificatesOf(_radarr);

      expect(settings.pinForUrl(_radarr.away!.url), _awayPin);
      expect(settings.pinForUrl(_radarr.url), isNull);
    });
  });

  group('the access each address sends', () {
    test('both addresses are in the pictures\' registry, each with its own '
        'access', () {
      final byAddress = {
        for (final (:url, :headers) in _settings.accessHeadersByAddress)
          url: headers,
      };

      expect(byAddress.keys, ['https://radarr.example.com']);
      expect(byAddress['https://radarr.example.com'], _token.headers());
    });

    test('the access at home goes with the address at home alone', () {
      const password = ProxyPassword(username: 'me', password: 'pw');
      final settings = _settings.copyWithInstance(
        _radarr.copyWith(access: password),
      );
      final byAddress = {
        for (final (:url, :headers) in settings.accessHeadersByAddress)
          url: headers,
      };

      expect(byAddress[_radarr.url], password.headers());
      expect(byAddress[_radarr.away!.url], _token.headers());
    });
  });

  group('a library grid keys its artwork on the route', () {
    test('at home: the address at home, with its access', () {
      expect(_settings.artworkKeyOf('radarr', ConnectionRoute.home), (
        _radarr.url,
        'radarr-key',
        const NoAccess(),
      ));
    });

    test('away: the address away, with the access its gateway asks for', () {
      expect(_settings.artworkKeyOf('radarr', ConnectionRoute.away), (
        'https://radarr.example.com',
        'radarr-key',
        _token,
      ));
    });

    test('a connection with one address stays at home on any route', () {
      expect(
        _settings.artworkKeyOf('sonarr', ConnectionRoute.away),
        _settings.artworkKeyOf('sonarr', ConnectionRoute.home),
      );
    });
  });
}

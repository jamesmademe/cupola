import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/local_network_target.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';

/// One answer to "is this host on the local network", wherever it is asked.
///
/// The local-network permission (`localNetworkHostVerdict`) is the source,
/// and the address field's cleartext warning (`UrlUtils.cleartextWarning`)
/// and the sign-in's warning before a password (`passwordTravelsInClear`)
/// follow it. They used to disagree: the field warned "off your local
/// network" for `http://nas.home.arpa:5055`, a host the permission rightly
/// treats as local.
void main() {
  /// `(host as a URL writes it, local?)`.
  const hosts = <(String, bool)>[
    ('nas.home.arpa:5055', true),
    ('nas.local', true),
    ('nas.lan', true),
    ('nas.internal', true),
    ('nas.home', true),
    ('nas.localdomain', true),
    ('nas', true),
    ('10.0.0.5', true),
    ('172.16.4.4', true),
    ('172.31.255.254', true),
    ('192.168.1.10:7878', true),
    ('169.254.7.7', true),
    ('[fd12:3456::1]', true),
    ('[fc00::1]', true),
    ('[fe80::1]', true),
    ('172.32.0.1', false),
    ('203.0.113.7', false),
    ('[2001:db8::1]', false),
    ('seerr.example.net', false),
    ('fdn.example.com', false),
  ];

  for (final (host, local) in hosts) {
    test(
      '$host reads ${local ? 'local' : 'off the local network'} everywhere',
      () {
        final bare = Uri.parse('http://$host').host;
        expect(
          localNetworkHostVerdict(bare) == true,
          local,
          reason: 'permission',
        );
        expect(
          UrlUtils.cleartextWarning('http://$host') == null,
          local,
          reason: 'the address field',
        );
        expect(
          passwordTravelsInClear('http://$host'),
          !local,
          reason: 'the sign-in',
        );
      },
    );
  }

  test('loopback never crosses a network, so nothing warns', () {
    for (final url in const [
      'http://localhost:5055',
      'http://127.0.0.1:5055',
      'http://[::1]:5055',
    ]) {
      expect(UrlUtils.cleartextWarning(url), isNull, reason: url);
      expect(passwordTravelsInClear(url), isFalse, reason: url);
    }
  });

  // Carrier NAT, Tailscale's range, and its MagicDNS names: the traffic
  // leaves through the tunnel, so the permission does not call it local, and
  // WireGuard encrypts it, so nothing warns about http://.
  test('a tailnet is not the local network, and nothing warns', () {
    for (final host in const [
      '100.64.1.2',
      '100.127.255.1',
      'nas.tail1234.ts.net',
    ]) {
      expect(localNetworkHostVerdict(host) == true, isFalse, reason: host);
      expect(UrlUtils.cleartextWarning('http://$host'), isNull, reason: host);
      expect(passwordTravelsInClear('http://$host'), isFalse, reason: host);
    }
    // Just outside the range, the internet again.
    expect(UrlUtils.cleartextWarning('http://100.128.0.1'), isNotNull);
    expect(UrlUtils.cleartextWarning('http://100.63.255.1'), isNotNull);
  });

  test('https never warns, wherever it goes', () {
    expect(UrlUtils.cleartextWarning('https://seerr.example.net'), isNull);
    expect(passwordTravelsInClear('https://seerr.example.net'), isFalse);
  });
}

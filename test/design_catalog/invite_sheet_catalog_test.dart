@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/invite_sheet.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/pair_fixtures.dart';
import 'catalog.dart';

late SharedPreferences _prefs;

const _homePin =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _awayPin =
    '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

const _home = 'https://nas.home.arpa:5055';
const _away = 'https://seerr.example.net';

ServiceInstance _seerr({
  String url = _home,
  ConnectionAccess access = const NoAccess(),
  ConnectionAddress? away = const ConnectionAddress(url: _away),
}) => ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: url,
  credential: 'catalog-key',
  access: access,
  away: away,
);

/// A scene's providers: the connection saved, and what the server says of
/// itself. A scene that overrides gets a container of its own, so these are
/// the whole set.
List<Override> _world(
  ServiceInstance connection, {
  Map<String, String> pins = const {},
  required Future<SeerrServerFacts> Function() facts,
  PairOfferState Function()? offer,
}) => [
  // The code shown in person, standing still: two minutes on the clock.
  inviteOfferProvider.overrideWith(
    () => FixedPairOffer(
      (offer ??
          () => PairOfferOpen(
            link: pairFixtureLink(invite: true),
            package: pairFixtureInvitePackage(),
          ))(),
    ),
  ),
  pairNetworkProvider.overrideWithValue(
    PairNetwork(now: () => DateTime.utc(2030, 1, 1, 12, 0, 8)),
  ),
  sharedPreferencesProvider.overrideWith((ref) => _prefs),
  secureSettingsStoreProvider.overrideWith((ref) => FakeSecureSettingsStore()),
  initialSettingsProvider.overrideWith(
    (ref) => SettingsModel(instances: [connection], trustedCertificates: pins),
  ),
  initialOnboardingCompletedProvider.overrideWith((ref) => true),
  seerrServerFactsProvider.overrideWith((ref, id) => facts()),
];

Future<SeerrServerFacts> _named(String? title) async =>
    SeerrServerFacts.fromPublicSettings({
      'initialized': true,
      'applicationTitle': ?title,
    });

/// The sheet as it stands open: the page under the modal barrier, and the
/// panel risen from the bottom edge. An open sheet is a route of its own and
/// paints above the page, so the scene draws the same panel in place.
Widget _open({double maxWidth = double.infinity}) => Builder(
  builder: (context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Theme.of(context).colorScheme.surface),
      // `showModalBottomSheet`'s default barrier.
      const ColoredBox(color: Colors.black54),
      Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: const InviteSheet(connectionId: 'seerr'),
        ),
      ),
    ],
  ),
);

CatalogScene _scene(
  String caption,
  List<Override> overrides, {
  double width = 390,
  double height = 720,
  double maxWidth = double.infinity,
  CatalogPlatform platform = CatalogPlatform.phone,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => _open(maxWidth: maxWidth),
  width: width,
  height: height,
  platform: platform,
  overrides: overrides,
  textScale: textScale,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  final bothAddresses = _world(
    _seerr(),
    pins: const {
      'https://nas.home.arpa:5055': _homePin,
      'https://seerr.example.net:443': _awayPin,
    },
    facts: () => _named('Rossi Movies'),
  );
  final homeOnly = _world(
    _seerr(url: 'http://192.168.1.10:5055', away: null),
    facts: () => _named(null),
  );
  List<Override> gated({PairOfferState Function()? offer}) => _world(
    _seerr(
      away: const ConnectionAddress(
        url: _away,
        access: CloudflareServiceToken(
          clientId: 'catalog-id',
          clientSecret: 'catalog-secret',
        ),
      ),
    ),
    pins: const {'https://nas.home.arpa:5055': _homePin},
    facts: () => _named('Rossi Movies'),
    offer: offer,
  );
  final awayGated = gated();
  final homeGated = _world(
    _seerr(
      url: 'http://192.168.1.10:5055',
      access: const ProxyPassword(
        username: 'catalog-user',
        password: 'catalog-password',
      ),
      away: null,
    ),
    facts: () => _named('Rossi Movies'),
  );

  catalogCard(
    'InviteSheet',
    width: 880,
    scenes: [
      _scene(
        'InviteSheet · both addresses, each with its certificate, and the '
        'server\'s name on the line under the code: nothing else to say',
        bothAddresses,
      ),
      _scene(
        'InviteSheet · an address at home only, and a server with no name of '
        'its own: the host alone under the code, one line of what it cannot do',
        homeOnly,
        height: 700,
      ),
      _scene(
        'InviteSheet · in person: the address away asks for a token a link '
        'never carries, so the sheet opens on a code that brings it, two '
        'minutes on the clock; the link is one tap away',
        awayGated,
        height: 800,
      ),
      _scene(
        'InviteSheet · in person, the address at home asking: what the code '
        'brings, and why the link does less',
        homeGated,
        height: 800,
      ),
      _scene(
        'InviteSheet · in person, taken by their phone: the code is closed, '
        'Done',
        gated(offer: () => PairOfferSent(pairFixtureInvitePackage())),
        height: 760,
      ),
      _scene(
        'InviteSheet · in person, the code closed unused: why, and Make a new '
        'code',
        gated(offer: () => const PairOfferClosed(PairServerEnd.expired)),
        height: 800,
      ),
      _scene(
        'InviteSheet · in person, off the Wi-Fi: blue, Retry, the link still '
        'a tap away',
        gated(offer: () => const PairOfferNoNetwork()),
        height: 520,
      ),
      _scene(
        'InviteSheet · on a desktop window: the modal sheet caps at 640pt '
        'wide, centred',
        bothAddresses,
        width: 832,
        maxWidth: 640,
        platform: CatalogPlatform.desktop,
      ),
      _scene(
        'Text at 200% · the code shown in person at twice the reading size, '
        'on a tall screen; on a phone it scrolls inside its 92% cap · the code '
        'keeps its side',
        awayGated,
        height: 1400,
        textScale: catalogTextScale,
      ),
    ],
  );
}

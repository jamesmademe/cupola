@Tags(['catalog'])
library;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/presentation/pair_offer_screen.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/pair_fixtures.dart';
import 'catalog.dart';

/// A scene's providers: the state the page stands in, and the clock a
/// countdown reads. No socket is opened: the notifier made here only says it
/// was asked.
List<Override> _world(PairOfferState state) => [
  fixedOfferOf(state),
  pairNetworkProvider.overrideWithValue(
    PairNetwork(
      now: () => pairFixtureLink().closesAt.subtract(
        const Duration(minutes: 1, seconds: 52),
      ),
    ),
  ),
];

PairOfferOpen _open({PairPackage? package}) => PairOfferOpen(
  link: pairFixtureLink(),
  package: package ?? pairFixturePackage(),
);

/// Twelve connections: the titles run past four, and are counted.
PairPackage _many() => PairPackage(
  from: PairDevice.iphone,
  connections: [
    for (final (index, service) in ServiceKey.values.take(12).indexed)
      ServiceInstance(
        id: 'c$index',
        service: service,
        url: 'http://192.168.1.10:${7000 + index}',
        credential: 'catalog-key',
      ),
  ],
);

/// A single service, nothing else travelling.
PairPackage _one() => PairPackage(
  from: PairDevice.iphone,
  connections: const [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://192.168.1.10:7878',
      credential: 'catalog-key',
    ),
  ],
);

CatalogScene _scene(
  String caption,
  PairOfferState state, {
  double height = 640,
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => const PairOfferScreen(),
  width: width,
  height: height,
  platform: platform,
  overrides: _world(state),
  textScale: textScale,
);

void main() {
  catalogCard(
    'PairOffer',
    width: 960,
    scenes: [
      _scene(
        'PairOffer · making the code: the square is held, a quiet spinner in '
        'it',
        const PairOfferPreparing(),
        height: 520,
      ),
      _scene(
        'PairOffer · the code is up: the QR, how to scan it and for how long, '
        'Copy link, what moves, why it is safe',
        _open(),
        height: 1040,
      ),
      _scene(
        'PairOffer · twelve services: the first four named, the rest counted',
        _open(package: _many()),
        height: 1000,
      ),
      _scene(
        'PairOffer · one service and nothing else',
        _open(package: _one()),
        height: 880,
      ),
      _scene(
        'PairOffer · on a Mac: Copy link is the way, and the firewall question '
        'is said',
        _open(),
        width: 860,
        height: 1040,
        platform: CatalogPlatform.desktop,
      ),
      _scene(
        'PairOffer · the other phone has it: a green check where the code '
        'was, the code closed',
        PairOfferSent(pairFixturePackage()),
        height: 560,
      ),
      _scene(
        'PairOffer · its two minutes are up: neutral, a new code on offer',
        const PairOfferClosed(PairServerEnd.expired),
        height: 560,
      ),
      _scene(
        'PairOffer · closed after three wrong requests',
        const PairOfferClosed(PairServerEnd.refused),
        height: 560,
      ),
      _scene(
        'PairOffer · no home network: blue, informational, Retry',
        const PairOfferNoNetwork(),
        height: 300,
      ),
      _scene(
        'PairOffer · the server did not open: amber, its one fill is the '
        'remedy',
        const PairOfferFailed(),
        height: 300,
      ),
      _scene(
        'Text at 200% · the code up, at twice the reading size: the page '
        'scrolls, the code keeps its side',
        _open(),
        height: 2800,
        textScale: catalogTextScale,
      ),
    ],
  );
}

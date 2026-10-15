@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/pairing/presentation/pair_receive_screen.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/pair_fixtures.dart';
import 'catalog.dart';

CatalogScene _scene(
  String caption,
  PairReceiveState state, {
  double height = 640,
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => const PairReceiveScreen(),
  width: width,
  height: height,
  platform: platform,
  overrides: [fixedReceiveOf(state)],
  textScale: textScale,
);

/// What the sending device hands over, and a Sonarr the new one has already.
PairPlan _plan() => pairFixturePlan(
  settings: const SettingsModel(
    instances: [
      ServiceInstance(
        id: 'sonarr',
        service: ServiceKey.sonarr,
        url: 'http://192.168.1.10:8989',
        credential: 'catalog-key',
      ),
    ],
  ),
);

/// Everything the sending device has is here already.
PairPlan _allHere() => PairPlan.of(pairFixturePackage(), pairFixtureSender());

/// Only a certificate is new, and a service this version does not know stays
/// behind.
PairPlan _onlyACertificate() => PairPlan.of(
  PairPackage(
    from: PairDevice.mac,
    connections: const [
      ServiceInstance(
        id: 'radarr',
        service: ServiceKey.radarr,
        url: 'https://radarr.home.arpa',
        credential: 'catalog-key',
      ),
    ],
    certificates: const {'https://radarr.home.arpa:443': pairFixturePin},
    unknown: 2,
  ),
  const SettingsModel(
    instances: [
      ServiceInstance(
        id: 'mine',
        service: ServiceKey.radarr,
        url: 'https://radarr.home.arpa',
        credential: 'catalog-key',
      ),
    ],
  ),
);

void main() {
  catalogCard(
    'PairReceive',
    width: 960,
    scenes: [
      _scene(
        'PairReceive · waiting for a link: point the camera at the code, or '
        'paste what was sent',
        const PairReceiveWaiting(),
        height: 460,
      ),
      _scene(
        'PairReceive · fetching: the busy line',
        const PairReceiveFetching(),
        height: 300,
      ),
      _scene(
        'PairReceive · on a Mac: the link is copied and pasted, there is no '
        'camera',
        const PairReceiveWaiting(),
        width: 860,
        height: 460,
        platform: CatalogPlatform.desktop,
      ),
      _scene(
        'PairReceive · the other device did not answer: red, Retry and Start '
        'again, both in ink',
        const PairReceiveFailed(PairReceiveFailure.unreachable),
        height: 360,
      ),
      _scene(
        'PairReceive · the code ran out: blue, Start again in ink',
        const PairReceiveFailed(PairReceiveFailure.expired),
        height: 300,
      ),
      _scene(
        'PairReceive · what arrived did not open: amber, Start again is the '
        'one fill',
        const PairReceiveFailed(PairReceiveFailure.unreadable),
        height: 320,
      ),
      _scene(
        'PairReceive · from a newer Cupola',
        const PairReceiveFailed(PairReceiveFailure.newer),
        height: 320,
      ),
      _scene(
        'PairReceive · a link that is not whole',
        const PairReceiveFailed(PairReceiveFailure.notWhole),
        height: 320,
      ),
      _scene(
        'PairReceive · what arrived: the connections by title and host, the '
        'notes that apply, Add, Start again',
        PairReceivePreview(_plan()),
        height: 840,
      ),
      _scene(
        'PairReceive · adding: the primary is busy and cannot be tapped twice',
        PairReceiveAdding(_plan()),
        height: 840,
      ),
      _scene(
        'PairReceive · only a certificate is new, and two services this '
        'version does not know stay behind',
        PairReceivePreview(_onlyACertificate()),
        height: 560,
      ),
      _scene(
        'PairReceive · everything is here already: Done',
        PairReceivePreview(_allHere()),
        height: 440,
      ),
      _scene(
        'Text at 200% · what arrived, at twice the reading size',
        PairReceivePreview(_plan()),
        height: 2600,
        textScale: catalogTextScale,
      ),
    ],
  );
}

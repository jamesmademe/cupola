@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/service_deck.dart';
import 'package:cupola/features/shell/presentation/desktop/shell_freshness.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import 'catalog.dart';

/// Two named Radarr connections, the lens on the first, so the chrome shows
/// its lens chip and the deck its connection name.
const _settings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'https://four-k.lan:7878',
      credential: 'k',
    ),
    ServiceInstance(
      id: 'radarr-hd11111',
      service: ServiceKey.radarr,
      label: 'HD',
      url: 'https://hd.lan:7879',
      credential: 'k',
    ),
  ],
);

const _threeDown = StackHealth(
  configured: 16,
  answering: 13,
  degraded: 0,
  unreachable: 3,
  checking: 0,
  notSetUp: 1,
);

const _stillChecking = StackHealth(
  configured: 16,
  answering: 11,
  degraded: 0,
  unreachable: 0,
  checking: 5,
  notSetUp: 1,
);

class _FixedHealth extends StackHealthNotifier {
  _FixedHealth(this.health);

  final StackHealth health;

  @override
  StackHealth build() => health;
}

late SharedPreferences _prefs;

/// One scene's own root container and router.
///
/// A nested `ProviderScope` only replaces the providers it names, so each
/// scene gets a container of its own; and the strips read the location, so
/// each is built as the one route of a router sitting at [location].
class _Scene extends StatefulWidget {
  const _Scene({
    required this.location,
    required this.child,
    this.health = _threeDown,
    this.refreshed = true,
  });

  final String location;
  final Widget child;
  final StackHealth health;
  final bool refreshed;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  late final _container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(_settings),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      stackHealthProvider.overrideWith(() => _FixedHealth(widget.health)),
      lastRefreshedAtProvider.overrideWith(
        (ref) => widget.refreshed
            ? DateTime.now().subtract(const Duration(minutes: 2))
            : null,
      ),
    ],
    retry: (_, _) => null,
  );

  late final _router = GoRouter(
    initialLocation: widget.location,
    routes: [_route(Uri.parse(widget.location).pathSegments, 0)],
  );

  GoRoute _route(List<String> segments, int index) {
    final leaf = index == segments.length - 1;
    return GoRoute(
      path: index == 0 ? '/${segments.first}' : segments[index],
      builder: (_, _) => leaf ? widget.child : const SizedBox.shrink(),
      routes: [if (!leaf) _route(segments, index + 1)],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: Router.withConfig(config: _router),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  /// The deck starts right of the 56pt rail.
  const deckWidth = 1280.0 - 56;

  catalogCard(
    'WindowChrome',
    width: 1328,
    scenes: [
      CatalogScene(
        'WindowChrome · full, inside Radarr on its 4K connection · the 72pt '
        'gutter AppKit draws the traffic lights in, the breadcrumb that is the '
        'window title, the lens readout and two chips',
        (_) => const _Scene(
          location: ServiceRoutes.radarrLibrary,
          child: WindowChrome(inspectorOpen: false),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowChrome · full, on Activity, inspector open · the inspector '
        'chip lit in the Activity accent; no lens outside a service',
        (_) => const _Scene(
          location: '/activity',
          child: WindowChrome(inspectorOpen: true),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowChrome · compact (a 960 window) · 38 tall; the chips keep '
        'glyph and key, the lens keeps only its glyph',
        (_) => const _Scene(
          location: ServiceRoutes.radarrLibrary,
          child: WindowChrome(inspectorOpen: true),
        ),
        width: 960,
        height: WindowChrome.compactHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceDeck · full, on a canonical tab · All services, the stack as '
        'one figure with its down count, the freshness line, the jump pill',
        (_) => _DeckScene(location: '/dashboard', onCommandDeck: () {}),
        width: deckWidth,
        height: ServiceDeck.fullHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        "ServiceDeck · full, on a service's tab root · no active chip and no "
        'accent: the service header below names the room',
        (_) => _DeckScene(
          location: ServiceRoutes.radarrLibrary,
          onCommandDeck: () {},
        ),
        width: deckWidth,
        height: ServiceDeck.fullHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceDeck · full, on a pushed page (a film) · the active chip '
        'returns with the connection name; probes still in flight add the '
        'neutral dot',
        (_) => _DeckScene(
          location: ServiceRoutes.radarrMovie(1),
          health: _stillChecking,
          onCommandDeck: () {},
        ),
        width: deckWidth,
        height: ServiceDeck.fullHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceDeck · compact (a 960 window), pushed page · 40 tall, the chip '
        'capped at 120 and the pill reading Jump',
        (_) => _DeckScene(
          location: ServiceRoutes.radarrMovie(1),
          compact: true,
          onCommandDeck: () {},
        ),
        width: 960 - 56,
        height: ServiceDeck.compactHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceDeck · under 500pt, never refreshed · the down count and the '
        'freshness line drop; the pill keeps only its key',
        (_) => _DeckScene(
          location: '/dashboard',
          compact: true,
          refreshed: false,
          onCommandDeck: () {},
        ),
        width: 440,
        height: ServiceDeck.compactHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowDragStrip · above a flow the shell does not host (onboarding) · '
        'the gutter and a dim trail that links nowhere',
        (_) => const WindowDragStrip(),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

/// A [ServiceDeck] at [location].
class _DeckScene extends StatelessWidget {
  const _DeckScene({
    required this.location,
    required this.onCommandDeck,
    this.compact = false,
    this.refreshed = true,
    this.health = _threeDown,
  });

  final String location;
  final VoidCallback onCommandDeck;
  final bool compact;
  final bool refreshed;
  final StackHealth health;

  @override
  Widget build(BuildContext context) => _Scene(
    location: location,
    health: health,
    refreshed: refreshed,
    child: ServiceDeck(compact: compact, onCommandDeck: onCommandDeck),
  );
}

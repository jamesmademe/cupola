@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/network/connection_failure.dart'
    show ServiceFailureReason;
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show dashboardDecisionsProvider, stallClockProvider;
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/shell/presentation/desktop/shortcuts_sheet.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import 'catalog.dart';

/// Two named Radarr connections, the lens on the first, so the chrome shows
/// its lens readout.
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

/// Activity's sources, all answered: `All 12 answered at 20:53`.
final _answered = SourceCoverage(
  answered: {
    for (final service in ServiceKey.values.take(12))
      CoverageSource(service, instanceId: service.name),
  },
);

/// One of them silent: `11 of 12 answered`, in red.
final _oneSilent = SourceCoverage(
  answered: {
    for (final service in ServiceKey.values.take(11))
      CoverageSource(service, instanceId: service.name),
  },
  failed: {
    CoverageSource(
      ServiceKey.values[11],
      instanceId: ServiceKey.values[11].name,
    ): ServiceFailureReason.unreachable,
  },
);

class _Requester extends ShellAudienceNotifier {
  @override
  Audience build() => Audience.requester;
}

late SharedPreferences _prefs;

/// One scene's own root container and router.
///
/// A nested `ProviderScope` only replaces the providers it names, so each
/// scene gets a container of its own; and the strips read the location, so
/// each is built as the one route of a router sitting at [location].
class _Scene extends StatefulWidget {
  _Scene({
    required this.location,
    required this.child,
    SourceCoverage? coverage,
    this.requester = false,
  }) : coverage = coverage ?? _answered;

  final String location;
  final Widget child;
  final SourceCoverage coverage;
  final bool requester;

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
      if (widget.requester) shellAudienceProvider.overrideWith(_Requester.new),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      dashboardDecisionsProvider.overrideWithValue((
        decisions: const [],
        coverage: widget.coverage,
      )),
      stallClockProvider.overrideWithValue(() => DateTime(2026, 10, 9, 20, 53)),
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

  catalogCard(
    'WindowChrome',
    width: 1328,
    scenes: [
      CatalogScene(
        'WindowChrome · full, inside Radarr on its 4K connection · the 72pt '
        'gutter AppKit draws the traffic lights in, the sidebar\'s switch, back '
        'and forward, the breadcrumb that is the '
        "window title, the lens readout, the way to anything and the "
        "inspector's switch",
        (_) => _Scene(
          location: ServiceRoutes.radarrLibrary,
          child: WindowChrome(inspectorOpen: false, onCommandDeck: () {}),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowChrome · full, on Activity, inspector open · who of its '
        'sources answered and when, the switch on (the strong fill under the '
        'primary ink); no lens outside a service',
        (_) => _Scene(
          location: '/activity',
          child: WindowChrome(inspectorOpen: true, onCommandDeck: () {}),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowChrome · on Activity with a source that did not answer · how '
        'many did, in red with its dot',
        (_) => _Scene(
          location: '/activity/downloads',
          coverage: _oneSilent,
          child: WindowChrome(inspectorOpen: false, onCommandDeck: () {}),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'WindowChrome · compact (a 960 window) · a Mac\'s 52 still (38 on '
        'Windows and Linux); the lens keeps only '
        'its glyph, the way to anything reads Jump, and no switch for a pane '
        'a compact window never lays out',
        (_) => _Scene(
          location: ServiceRoutes.radarrLibrary,
          child: WindowChrome(inspectorOpen: true, onCommandDeck: () {}),
        ),
        width: 960,
        height: WindowChrome.compactHeight,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        "WindowChrome · the requester's window · the arrows, the breadcrumb "
        'and refresh: no command deck and no inspector',
        (_) => _Scene(
          location: '/home',
          requester: true,
          child: const WindowChrome(inspectorOpen: false),
        ),
        width: 1280,
        height: WindowChrome.height,
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
      CatalogScene(
        'ShortcutsSheet · ⌘/ · every key of the window in the order a person '
        'reaches for them, from the one map the bindings read',
        (_) => const Center(child: ShortcutsSheet(requester: false)),
        width: 560,
        height: 620,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · WindowChrome, full, on Activity: the breadcrumb, the '
        'answer line, the way to anything and the switch in their 44pt row',
        (_) => _Scene(
          location: '/activity',
          child: WindowChrome(inspectorOpen: true, onCommandDeck: () {}),
        ),
        width: 1280,
        height: WindowChrome.height,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

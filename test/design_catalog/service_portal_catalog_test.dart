@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/presentation/portal_coach_mark.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/fake_services.dart';
import 'catalog.dart';

const _instances = [
  ServiceInstance(
    id: 'seerr',
    service: ServiceKey.seerr,
    url: 'https://requests.lan',
    credential: 'k',
  ),
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
  ServiceInstance(
    id: 'sonarr',
    service: ServiceKey.sonarr,
    url: 'https://sonarr.lan:8989',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'lidarr',
    service: ServiceKey.lidarr,
    url: 'https://lidarr.lan:8686',
    credential: 'k',
  ),
];

final _now = DateTime.now();

RadarrMovie _movie(int id, String title, int year, {bool poster = false}) =>
    RadarrMovie(
      id: id,
      title: title,
      sortTitle: title.toLowerCase(),
      sizeOnDisk: 0,
      status: 'released',
      hasFile: true,
      monitored: true,
      year: year,
      images: poster
          ? const [
              {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
            ]
          : const [],
      tmdbId: id,
      runtime: 90,
      genres: const [],
      added: DateTime(_now.year, _now.month, _now.day).toIso8601String(),
    );

class _Radarr extends FakeRadarrService {
  @override
  Future<List<RadarrMovie>> getMovies() async => [
    _movie(1, 'Nosferatu', 1922, poster: true),
    _movie(2, 'Metropolis', 1927),
    _movie(3, 'The Cabinet of Dr. Caligari', 1920),
    _movie(4, 'Sherlock Jr.', 1924),
  ];
}

ServiceSummary _summary(ServiceKey service, {bool online = true}) =>
    ServiceSummary(
      service: service,
      status: online
          ? ServiceSummaryStatus.online
          : ServiceSummaryStatus.offline,
      host: 'lan',
      version: '5.14.0',
    );

/// The operator's bar: the Portal is the Stack tab's gesture.
final _bar = NavTab.barFor(Audience.operator);

List<FloatingNavDestination> _destinations() => [
  for (final tab in _bar)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
    ),
];

late SharedPreferences _prefs;

/// The phone shell's touch layout — the stage over the page, the coach mark,
/// the bar that drives the Portal — held at portal value [t].
///
/// The value is set after the page has loaded: the card freezes the page to a
/// texture on its first frame above zero, so setting it on the first frame
/// would freeze the loading state.
class _PortalPose extends StatefulWidget {
  const _PortalPose(this.t);

  final double t;

  @override
  State<_PortalPose> createState() => _PortalPoseState();
}

class _PortalPoseState extends State<_PortalPose>
    with TickerProviderStateMixin {
  late final _portal = ServicePortalController(vsync: this);
  final _radarr = _Radarr();

  late final _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(
        const SettingsModel(instances: _instances),
      ),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      for (final instance in _instances)
        instanceSummaryProvider((
          service: instance.service,
          instanceId: instance.id,
        )).overrideWith(
          (ref) async => _summary(
            instance.service,
            online: instance.service != ServiceKey.lidarr,
          ),
        ),
      radarrServiceProvider.overrideWithValue(_radarr),
      radarrServiceForProvider.overrideWith((ref, id) => _radarr),
      sonarrServiceProvider.overrideWithValue(FakeSonarrService()),
      sonarrServiceForProvider.overrideWith((ref, id) => FakeSonarrService()),
      lidarrServiceProvider.overrideWithValue(FakeLidarrService()),
      lidarrServiceForProvider.overrideWith((ref, id) => FakeLidarrService()),
      seerrServiceProvider.overrideWithValue(FakeSeerrService()),
      seerrServiceForProvider.overrideWith((ref, id) => FakeSeerrService()),
    ],
    retry: (_, _) => null,
  );

  late final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          extendBody: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              PortalStage(
                controller: _portal,
                child: const RadarrOverviewScreen(topPadding: 0),
              ),
              PortalCoachMark(controller: _portal),
            ],
          ),
          bottomNavigationBar: FloatingBottomNavBar(
            selectedIndex: _bar.indexOf(NavTab.stack),
            onDestinationSelected: (_) {},
            destinations: _destinations(),
            verticalDragDelegate: _portal,
          ),
        ),
      ),
    ],
  );

  Timer? _pose;

  @override
  void initState() {
    super.initState();
    if (widget.t > 0) {
      _pose = Timer(const Duration(seconds: 2), () {
        _portal.portal.value = widget.t;
        // Painted live rather than from the frozen texture: a widget test
        // rasterises that texture without its artwork, which would draw the
        // poster as a black plate the app never shows.
        _portal.snapshot.allowSnapshotting = false;
      });
    }
  }

  @override
  void dispose() {
    _pose?.cancel();
    _router.dispose();
    _portal.dispose();
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
    // Three manual switches without the Portal: the coach mark is due.
    SharedPreferences.setMockInitialValues({
      'portal_manual_journeys': 3,
      'portal_hint_demo_shown': true,
    });
    _prefs = await SharedPreferences.getInstance();
  });

  const phone = Size(390, 844);

  catalogCard(
    'ServicePortal',
    scenes: [
      CatalogScene(
        'PortalStage · at rest, t = 0, with PortalCoachMark · nothing is '
        'mounted but the page; the hint sits space-sm above the bar',
        (_) => const _PortalPose(0),
        width: phone.width,
        height: phone.height,
      ),
      CatalogScene(
        'PortalStage · mid-gesture, t = 0.45 · the card recedes on a linear '
        'map, its corner already at 22; the floor fades in over it',
        (_) => const _PortalPose(0.45),
        width: phone.width,
        height: phone.height,
      ),
      CatalogScene(
        'PortalStage · open, t = 1 · the card at 42% under a 34pt inset, the '
        'ServiceMatrix picker on the floor; Lidarr did not answer',
        (_) => const _PortalPose(1),
        width: phone.width,
        height: phone.height,
      ),
      CatalogScene(
        'Text at 200% · PortalStage at rest with the coach mark',
        (_) => const _PortalPose(0),
        width: phone.width,
        height: phone.height,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · PortalStage open, t = 1: the ServiceMatrix picker on '
        'the floor at twice the reading size',
        (_) => const _PortalPose(1),
        width: phone.width,
        height: phone.height,
        textScale: catalogTextScale,
      ),
    ],
  );
}

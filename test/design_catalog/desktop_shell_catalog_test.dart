@Tags(['catalog'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_shell.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/fake_services.dart';
import 'catalog.dart';

const _settings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '',
      url: 'https://radarr.lan:7878',
      credential: 'k',
    ),
  ],
);

const _health = StackHealth(
  configured: 16,
  answering: 13,
  degraded: 0,
  unreachable: 3,
  checking: 0,
  notSetUp: 1,
);

class _FixedHealth extends StackHealthNotifier {
  @override
  StackHealth build() => _health;
}

final _now = catalogNow;
String _earlierToday(Duration ago) {
  final start = DateTime(_now.year, _now.month, _now.day);
  final at = _now.subtract(ago);
  return (at.isBefore(start) ? start : at).toIso8601String();
}

RadarrMovie _movie(int id, String title, int year, {bool poster = false}) =>
    RadarrMovie(
      id: id,
      title: title,
      sortTitle: title.toLowerCase(),
      sizeOnDisk: 0,
      status: 'released',
      hasFile: id != 2,
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
      added: _earlierToday(Duration(hours: id)),
      digitalRelease: id == 2
          ? DateTime(_now.year, _now.month, _now.day + 1, 9).toIso8601String()
          : null,
    );

final _library = [
  _movie(1, 'Nosferatu', 1922, poster: true),
  _movie(2, 'Metropolis', 1927),
  _movie(3, 'The Cabinet of Dr. Caligari', 1920),
  _movie(4, 'Sherlock Jr.', 1924),
];

class _Radarr extends FakeRadarrService {
  @override
  Future<List<RadarrMovie>> getMovies() async => _library;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => [
    {
      'movie': {'id': 2, 'title': 'Metropolis'},
      'trackedDownloadState': 'downloading',
      'status': 'warning',
      'errorMessage': 'The download is stalled with no connections',
      'downloadClient': 'qBittorrent',
      'added': _earlierToday(const Duration(hours: 1)),
    },
  ];

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => [
    {
      'movie': {'title': 'Nosferatu'},
      'eventType': 'downloadFolderImported',
      'quality': {
        'quality': {'name': 'Bluray-1080p'},
      },
      'size': 8053063680,
      'date': _earlierToday(const Duration(minutes: 20)),
    },
  ];

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const ArrRecordPage(records: [], total: 3);
}

class _StatusClient extends ApiClient {
  _StatusClient() : super(baseUrl: 'https://radarr.lan:7878', apiKey: 'k');

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async => Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'version': '5.14.0'},
  );

  @override
  void close({bool force = false}) {}
}

GlobalActivityItem _transfer(
  ServiceKey service,
  String title,
  String subtitle,
  double progress, {
  bool stalled = false,
}) => GlobalActivityItem(
  kind: GlobalActivityKind.queue,
  service: service,
  serviceType: ServiceType.movies,
  title: title,
  subtitle: subtitle,
  status: MediaStatusInfo(
    labelOverride: stalled ? 'Stuck' : 'Downloading',
    toneOverride: stalled ? StatusTone.warning : StatusTone.info,
    hasWarning: stalled,
    progress: progress,
  ),
);

final _queue = ActivityFeed(
  items: [
    _transfer(
      ServiceKey.radarr,
      'Nosferatu (1922)',
      'Nosferatu.1922.1080p.BluRay.x264-GROUP',
      0.71,
    ),
    _transfer(
      ServiceKey.radarr,
      'Metropolis (1927)',
      'Metropolis.1927.1080p.BluRay.x264-GROUP',
      0.18,
      stalled: true,
    ),
    _transfer(
      ServiceKey.sonarr,
      'Severance',
      "S2 E5 · Trojan's Horse · Severance.S02E05.1080p.WEB-DL-GROUP",
      0.54,
    ),
  ],
  results: const [],
);

/// The operator's bar, which the rail draws above Settings.
final _bar = NavTab.barFor(Audience.operator);

List<FloatingNavDestination> _destinations() => [
  for (final tab in _bar)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? 2 : 0,
      badgeTone: tab == NavTab.activity ? StatusTone.info : null,
      badgeSemanticLabel: tab == NavTab.activity
          ? '2 finished searches to look at'
          : null,
    ),
];

late SharedPreferences _prefs;

/// The requester's connection: her own Seerr account, which may only ask.
const _herSettings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'https://seerr.lan',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.local,
        login: 'anna@home.lan',
        userId: 7,
        displayName: 'Anna',
        session: 'session',
        permissions: 32,
      ),
    ),
  ],
);

/// The sidebar's services as a stack of sixteen reads them: Seerr's requests
/// wait, Sonarr and Prowlarr did not answer, the rest are calm.
const _railServices = <DesktopRailService>[
  (
    service: ServiceKey.seerr,
    tone: StatusTone.info,
    state: '2 requests wait for approval',
    count: '2',
  ),
  (service: ServiceKey.jellyfin, tone: null, state: null, count: null),
  (service: ServiceKey.radarr, tone: null, state: null, count: null),
  (
    service: ServiceKey.sonarr,
    tone: StatusTone.error,
    state: 'did not answer',
    count: null,
  ),
  (service: ServiceKey.lidarr, tone: null, state: null, count: null),
  (service: ServiceKey.bazarr, tone: null, state: null, count: null),
  (
    service: ServiceKey.prowlarr,
    tone: StatusTone.error,
    state: 'did not answer',
    count: null,
  ),
  (service: ServiceKey.qbittorrent, tone: null, state: null, count: null),
  (service: ServiceKey.sabnzbd, tone: null, state: null, count: null),
  (service: ServiceKey.truenas, tone: null, state: null, count: null),
  (service: ServiceKey.dockge, tone: null, state: null, count: null),
];

class _Requester extends ShellAudienceNotifier {
  @override
  Audience build() => Audience.requester;
}

/// The window at Radarr's Overview, with its own root container and router;
/// or, for [requester], her window on her page of requests.
class _Window extends StatefulWidget {
  const _Window() : requester = false;
  const _Window.requester() : requester = true;

  final bool requester;

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> {
  final _radarr = _Radarr();

  late final _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(
        widget.requester ? _herSettings : _settings,
      ),
      desktopRailServicesProvider.overrideWithValue(_railServices),
      // The sidebar's "In flight" poll: the sheet is a still.
      sidebarInFlightPollProvider.overrideWith((ref) {}),
      if (widget.requester) ...[
        shellAudienceProvider.overrideWith(_Requester.new),
        requestsProvider.overrideWith((ref) async => const []),
      ],
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      stackHealthProvider.overrideWith(_FixedHealth.new),
      radarrServiceProvider.overrideWithValue(_radarr),
      radarrServiceForProvider.overrideWith((ref, id) => _radarr),
      serviceStatusClientFactoryProvider.overrideWithValue(
        ({
          required String baseUrl,
          required String apiKey,
          String? pinnedCertFingerprint,
          Map<String, String> accessHeaders = const {},
        }) => _StatusClient(),
      ),
      globalNowItemsProvider.overrideWith((ref) async => _queue),
      unreachableServicesProvider.overrideWithValue(const [
        ServiceKey.sonarr,
        ServiceKey.prowlarr,
      ]),
    ],
    retry: (_, _) => null,
  );

  late final _router = GoRouter(
    initialLocation: widget.requester
        ? ServiceRoutes.requests
        : ServiceRoutes.radarrOverview,
    routes: [
      GoRoute(
        path: ServiceRoutes.requests,
        builder: (_, _) => DesktopShell(
          navigationShell: const RequestsScreen(),
          currentTab: NavTab.requests,
          destinations: [
            for (final tab in NavTab.barFor(Audience.requester))
              FloatingNavDestination(
                icon: tab.icon,
                selectedIcon: tab.selectedIcon,
                railIcon: tab.railIcon,
                label: tab.label,
              ),
          ],
          selectedIndex: NavTab.barFor(
            Audience.requester,
          ).indexOf(NavTab.requests),
          onDestinationSelected: (_) {},
          onSettings: () {},
        ),
      ),
      GoRoute(
        path: '/stack',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'radarr',
            builder: (_, _) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'overview',
                builder: (_, _) => DesktopShell(
                  navigationShell: const ServiceTabScaffold(
                    service: ServiceKey.radarr,
                    tab: ServiceTab.overview,
                    child: RadarrOverviewScreen(
                      topPadding: kToolbarHeight + ServiceTabBar.height,
                    ),
                  ),
                  currentTab: NavTab.stack,
                  destinations: _destinations(),
                  selectedIndex: _bar.indexOf(NavTab.stack),
                  onDestinationSelected: (_) {},
                  onSettings: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

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
    // The inspector switched on, as a person who uses it leaves it: with no
    // download chosen it is still not laid out.
    SharedPreferences.setMockInitialValues({'inspector_open': true});
    _prefs = await SharedPreferences.getInstance();
  });

  catalogCard(
    'DesktopShell',
    width: 1328,
    scenes: [
      CatalogScene(
        'DesktopShell · a 1280 × 800 window on Radarr Overview, nothing chosen '
        '· chrome, sidebar with In flight at its foot, the page under its lit '
        'service header and no inspector: its switch is dimmed until a '
        'download is chosen in Activity',
        (_) => const _Window(),
        width: 1280,
        height: 800,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopShell · a 960 × 640 window, same page · compact: the toolbar '
        'over the whole window again (a Mac\'s 52, 38 elsewhere), '
        'the folded rail, and no inspector under 1100',
        (_) => const _Window(),
        width: 960,
        height: 640,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopShell · the requester\'s 1280 × 800 window on her Requests · '
        'her three sections and no service, no deck and no command deck, no '
        'inspector; her page in the reading well',
        (_) => const _Window.requester(),
        width: 1280,
        height: 800,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopShell · a 1280 × 800 window at 200% reading size: the chrome, '
        'sidebar and page header with their text doubled',
        (_) => const _Window(),
        width: 1280,
        height: 800,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

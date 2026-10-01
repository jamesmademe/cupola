@Tags(['catalog'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_shell.dart';
import 'package:cupola/features/shell/presentation/desktop/shell_freshness.dart';

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

final _now = DateTime.now();
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
      ServiceKey.qbittorrent,
      'Nosferatu.1922.1080p.BluRay.x264',
      '5.3 GB of 7.5 GB · 12.4 MB/s · 3 min',
      0.71,
    ),
    _transfer(
      ServiceKey.qbittorrent,
      'Metropolis.1927.1080p.BluRay.x264',
      '1.8 GB of 10.0 GB · 0 B/s · stalled',
      0.18,
      stalled: true,
    ),
    _transfer(
      ServiceKey.sabnzbd,
      'The.Cabinet.of.Dr.Caligari.1920.720p.BluRay.x264',
      '2.2 GB of 4.1 GB · 38.0 MB/s · 1 min',
      0.54,
    ),
  ],
  results: const [],
);

List<FloatingNavDestination> _destinations() => [
  for (final tab in NavTab.values)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? 2 : 0,
      badgeSemanticLabel: tab == NavTab.activity
          ? '2 finished searches to look at'
          : null,
    ),
];

late SharedPreferences _prefs;

/// The window at Radarr's Overview, with its own root container and router.
class _Window extends StatefulWidget {
  const _Window();

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> {
  final _radarr = _Radarr();

  late final _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(_settings),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      stackHealthProvider.overrideWith(_FixedHealth.new),
      lastRefreshedAtProvider.overrideWith(
        (ref) => _now.subtract(const Duration(minutes: 2)),
      ),
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
    initialLocation: ServiceRoutes.radarrOverview,
    routes: [
      GoRoute(
        path: '/dashboard',
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
                  destinations: _destinations(),
                  selectedIndex: NavTab.dashboard.index,
                  onDestinationSelected: (_) {},
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
    // The inspector's persisted state: open.
    SharedPreferences.setMockInitialValues({'inspector_open': true});
    _prefs = await SharedPreferences.getInstance();
  });

  catalogCard(
    'DesktopShell',
    width: 1328,
    scenes: [
      CatalogScene(
        'DesktopShell · a 1280 × 800 window on Radarr Overview, inspector open '
        '· chrome, rail, deck, the page under its lit service header, the '
        'split handle and the inspector; the deck drops its chip because the '
        'header names the room',
        (_) => const _Window(),
        width: 1280,
        height: 800,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopShell · a 960 × 640 window, same page, inspector still switched '
        'on · compact: 38pt chrome, 40pt deck, and no inspector under 1100',
        (_) => const _Window(),
        width: 960,
        height: 640,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

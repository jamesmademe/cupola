@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/main.dart' as cupola;

import '../test/test_helpers/settings_scope.dart';

/// Native route/state/visual matrix for the disposable OrbStack lab.
///
/// This test deliberately injects the lab settings into a test-only
/// ProviderScope instead of typing credentials through the onboarding UI on
/// every run. The real onboarding path remains covered separately; this is the
/// repeatable way to reach every service surface and collect evidence without
/// putting credentials in source control or coupling the matrix to OS input
/// automation.
///
/// The matrix covers every tab root, every TrueNAS section root, the global
/// shell/settings roots, and the detail/editor routes that are reachable from
/// those roots. The ids are deterministic lab specimens; a real instance is
/// still required to prove populated data and mutating actions.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment(
    'CUPOLA_MACLAB_SCREENSHOTS',
    defaultValue: true,
  );
  const driverScreenshots = bool.fromEnvironment(
    'CUPOLA_MACLAB_DRIVER_SCREENSHOTS',
    defaultValue: false,
  );

  testWidgets(
    'Cupola macOS lab route matrix: every tab, size and theme',
    (tester) async {
      final credentials = _loadCredentials();
      final allRoutes = _routes();
      final routeOffset =
          int.tryParse(
            Platform.environment['CUPOLA_MACLAB_ROUTE_OFFSET'] ?? '',
          ) ??
          0;
      final routeLimit = int.tryParse(
        Platform.environment['CUPOLA_MACLAB_ROUTE_LIMIT'] ?? '',
      );
      final routes = allRoutes
          .skip(routeOffset.clamp(0, allRoutes.length))
          .take(
            routeLimit != null && routeLimit > 0
                ? routeLimit
                : allRoutes.length,
          )
          .toList(growable: false);
      final allSizes = <({String name, Size size})>[
        (name: '1440x900', size: const Size(1440, 900)),
        (name: '720x450', size: const Size(720, 450)),
        (name: '390x844', size: const Size(390, 844)),
      ];
      final requestedSize = Platform.environment['CUPOLA_MACLAB_SIZE'];
      final sizes = requestedSize == null
          ? allSizes
          : allSizes
                .where((frame) => frame.name == requestedSize)
                .toList(growable: false);
      if (sizes.isEmpty) {
        fail(
          'CUPOLA_MACLAB_SIZE must be one of: '
          '${allSizes.map((frame) => frame.name).join(', ')}',
        );
      }
      final themes = <({String name, AppThemeMode mode})>[
        (name: 'dark', mode: AppThemeMode.dark),
        (name: 'light', mode: AppThemeMode.light),
      ];

      final screenshotDirectory = driverScreenshots
          ? null
          : (Directory(
              Platform.environment['CUPOLA_MACLAB_SCREENSHOT_DIR'] ??
                  '.ai/scratch/zz_maclab/screenshots',
            )..createSync(recursive: true));
      debugPrint(
        '[maclab] capture=$capture cwd=${Directory.current.path} '
        'screenshots=${screenshotDirectory?.absolute.path ?? 'driver'} '
        'routes=${routes.length}/${allRoutes.length} offset=$routeOffset',
      );

      for (final theme in themes) {
        final settings = _labSettings(credentials, theme.mode);
        final container = ProviderContainer(
          overrides: [
            ...await settingsScopeOverrides(customize: (_) => settings),
          ],
        );
        final router = container.read(routerProvider);
        final screenshotKey = GlobalKey();

        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: screenshotKey,
                child: const cupola.CupolaApp(),
              ),
            ),
          );
          await _pumpRoute(tester);

          for (final frame in sizes) {
            tester.view.physicalSize = frame.size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '${theme.name} · ${frame.name} · resize',
            );

            for (final route in routes) {
              if (Platform.environment['CUPOLA_MACLAB_VERBOSE'] == 'true') {
                debugPrint('[maclab] ${theme.name} · ${frame.name} · $route');
              }
              router.go(route);
              await _pumpRoute(tester);
              final exception = tester.takeException();

              if (capture) {
                final slug = _slug('${theme.name}_${frame.name}_$route');
                final bytes = await _captureScreenshot(screenshotKey);
                if (driverScreenshots) {
                  _addDriverScreenshot(binding, slug, bytes);
                } else {
                  await File(
                    '${screenshotDirectory!.path}/$slug.png',
                  ).writeAsBytes(bytes, flush: true);
                }
              }

              if (exception != null &&
                  Platform.environment['CUPOLA_MACLAB_VERBOSE'] == 'true') {
                debugPrint(
                  exception is FlutterError
                      ? exception.toStringDeep()
                      : exception.toString(),
                );
              }
              expect(
                exception,
                isNull,
                reason: '${theme.name} · ${frame.name} · $route',
              );
            }
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          router.dispose();
          container.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<List<int>> _captureScreenshot(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    fail('Screenshot boundary is not mounted');
  }
  final image = await boundary.toImage(pixelRatio: 1.0);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) fail('Flutter returned no PNG bytes');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void _addDriverScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  List<int> bytes,
) {
  final data = binding.reportData ??= <String, dynamic>{};
  final screenshots =
      data.putIfAbsent('screenshots', () => <dynamic>[]) as List<dynamic>;
  screenshots.add(<String, dynamic>{'screenshotName': name, 'bytes': bytes});
}

Future<void> _pumpRoute(WidgetTester tester) async {
  // The service ring and polling surfaces can animate forever. The matrix is
  // about settled layout and route construction, so it disables authored
  // motion and gives network-backed providers a bounded window to paint.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(seconds: 2));
}

List<String> _routes() {
  final routes = <String>[
    ServiceRoutes.dashboard,
    '/activity',
    '/search',
    '/settings',
    '/settings/appearance',
    '/settings/background-search',
    '/settings/certificates',
    '/settings/connections',
    '/settings/hints',
    '/settings/region',
    for (final service in ServiceKey.values)
      '/settings/service/${service.routeParam}',
    for (final service in ServiceKey.values)
      for (final tab in tabsFor(service) ?? const <ServiceTab>[])
        '${ServiceRoutes.forService(service)}/${tab.segment}',
    ServiceRoutes.seerrMoviesAll,
    ServiceRoutes.seerrTvAll,
    ServiceRoutes.seerrTrendingAll,
    ServiceRoutes.seerrGenre(mediaType: 'movie', genreId: 28, title: 'Action'),
    ServiceRoutes.seerrDetail(mediaType: 'movie', id: 42),
    ServiceRoutes.seerrDetail(mediaType: 'tv', id: 55),
    ServiceRoutes.seerrPerson(287),
    ServiceRoutes.seerrCollection(10),
    ServiceRoutes.radarrMovie(42),
    ServiceRoutes.sonarrSeries(55),
    ServiceRoutes.lidarrArtist(9),
    ServiceRoutes.qbittorrentTorrent('abc123'),
    ServiceRoutes.bazarrSeries(7),
    ServiceRoutes.bazarrMovie(12),
    ServiceRoutes.prowlarrIndexer(3),
    ServiceRoutes.prowlarrSettings,
    for (final kind in ProwlarrProviderKind.values)
      ServiceRoutes.prowlarrSettingsSection(kind),
    ServiceRoutes.dockgeNewStack,
    ServiceRoutes.dockgeStack('immich'),
    ServiceRoutes.dockgeStackEdit('immich'),
    ServiceRoutes.jellyfinLibrary('f137a2dd', title: 'Films'),
    ServiceRoutes.jellyfinItem('abc-123'),
    ServiceRoutes.plexLibrary('1', title: 'Films'),
    ServiceRoutes.plexItem('9421'),
    ServiceRoutes.truenasDashboard,
    ServiceRoutes.truenasStorage,
    ServiceRoutes.truenasDatasets,
    ServiceRoutes.truenasShares,
    ServiceRoutes.truenasDataProtection,
    ServiceRoutes.truenasContainers,
    ServiceRoutes.truenasVms,
    ServiceRoutes.truenasApps,
    ServiceRoutes.truenasReporting,
    ServiceRoutes.truenasSystem,
    ServiceRoutes.truenasPool('tank'),
    ServiceRoutes.truenasDataset('tank/media'),
    ServiceRoutes.truenasContainer('c1'),
    ServiceRoutes.truenasVm('vm1'),
    ServiceRoutes.truenasApp('appname'),
    for (final section in const [
      'general',
      'advanced',
      'services',
      'network',
      'credentials',
      'certificates',
      'email',
      'update',
      'ntp',
      'alert-settings',
    ])
      '${ServiceRoutes.truenasSystem}/$section',
  ];
  return routes.toSet().toList(growable: false);
}

SettingsModel _labSettings(
  Map<String, String> credentials,
  AppThemeMode theme,
) {
  return settingsWith(
    themeMode: theme,
    plexClientId: 'cupola-maclab-ui-matrix',
    seerrUrl: 'http://127.0.0.1:5055',
    seerrApiKey: _required(credentials, 'CUPOLA_MACLAB_SEERR_API_KEY'),
    radarrUrl: 'http://127.0.0.1:7878',
    radarrApiKey: 'test-key',
    sonarrUrl: 'http://127.0.0.1:8989',
    sonarrApiKey: 'test-key',
    lidarrUrl: 'http://127.0.0.1:8686',
    lidarrApiKey: 'test-key',
    readarrUrl: 'http://127.0.0.1:8787',
    readarrApiKey: 'test-key',
    prowlarrUrl: 'http://127.0.0.1:9696',
    prowlarrApiKey: 'test-key',
    bazarrUrl: 'http://127.0.0.1:6767',
    bazarrApiKey: 'test-key',
    qbittorrentUrl: 'http://127.0.0.1:8080',
    qbittorrentUsername: _required(
      credentials,
      'CUPOLA_MACLAB_QBITTORRENT_USERNAME',
    ),
    qbittorrentPassword: _required(
      credentials,
      'CUPOLA_MACLAB_QBITTORRENT_PASSWORD',
    ),
    transmissionUrl: 'http://127.0.0.1:9091',
    transmissionUsername: _required(
      credentials,
      'CUPOLA_MACLAB_TRANSMISSION_USERNAME',
    ),
    transmissionPassword: _required(
      credentials,
      'CUPOLA_MACLAB_TRANSMISSION_PASSWORD',
    ),
    sabnzbdUrl: 'http://127.0.0.1:8082',
    sabnzbdApiKey: 'test-key',
    nzbgetUrl: 'http://127.0.0.1:6789',
    nzbgetUsername: _required(credentials, 'CUPOLA_MACLAB_NZBGET_USERNAME'),
    nzbgetPassword: _required(credentials, 'CUPOLA_MACLAB_NZBGET_PASSWORD'),
    jellyfinUrl: 'http://127.0.0.1:8096',
    jellyfinApiKey: _required(credentials, 'CUPOLA_MACLAB_JELLYFIN_TOKEN'),
    jellyfinUserId: _required(credentials, 'CUPOLA_MACLAB_JELLYFIN_USER_ID'),
    plexUrl: 'http://127.0.0.1:32400',
    plexToken: _required(credentials, 'CUPOLA_MACLAB_PLEX_TOKEN'),
    dockgeUrl: 'http://127.0.0.1:5001',
    dockgeUsername: _required(credentials, 'CUPOLA_MACLAB_DOCKGE_USERNAME'),
    dockgePassword: _required(credentials, 'CUPOLA_MACLAB_DOCKGE_PASSWORD'),
    npmUrl: 'http://127.0.0.1:8181',
    npmUsername: _required(credentials, 'CUPOLA_MACLAB_NPM_USERNAME'),
    npmPassword: _required(credentials, 'CUPOLA_MACLAB_NPM_PASSWORD'),
    truenasUrl: 'ws://127.0.0.1:8460',
    truenasApiKey: 'test-key',
    unraidUrl: 'http://127.0.0.1:8480',
    unraidApiKey: 'test-key',
  );
}

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_MACLAB_CREDENTIALS_FILE'];
  final values = <String, String>{};
  // A native macOS integration-test runner is sandboxed away from the
  // checkout, while the Dart VM transport test can read the disposable file
  // directly. Prefer it when available, then fall back to inherited
  // CUPOLA_MACLAB_* variables for the native runner. The bootstrap file is
  // still the only source of the values; this fallback avoids putting them in
  // source control or in command-line arguments.
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        values[line.substring(0, separator)] = line.substring(separator + 1);
      }
    } on FileSystemException {
      // The native test app cannot see the host checkout; use its environment
      // below instead.
    }
  }
  for (final entry in Platform.environment.entries) {
    if (entry.key.startsWith('CUPOLA_MACLAB_')) {
      values.putIfAbsent(entry.key, () => entry.value);
    }
  }
  if (values.isEmpty) {
    fail(
      'Provide CUPOLA_MACLAB_* environment variables from the bootstrap '
      'credentials.env, or a readable CUPOLA_MACLAB_CREDENTIALS_FILE',
    );
  }
  return values;
}

String _required(Map<String, String> values, String key) {
  final value = values[key];
  if (value == null || value.isEmpty) fail('Missing $key in lab credentials');
  return value;
}

String _slug(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

@Tags(['catalog'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/fake_services.dart';
import 'catalog.dart';

const _oneRadarr = SettingsModel(
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

/// Two connections, so the identity line carries the lens chip.
const _twoRadarrs = SettingsModel(
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

final _now = DateTime.now();

/// A moment earlier today, never yesterday, so History today keeps it.
String _earlierToday(Duration ago) {
  final start = DateTime(_now.year, _now.month, _now.day);
  final at = _now.subtract(ago);
  return (at.isBefore(start) ? start : at).toIso8601String();
}

String _inDays(int days) =>
    DateTime(_now.year, _now.month, _now.day + days, 9).toIso8601String();

RadarrMovie _movie(
  int id,
  String title,
  int year, {
  bool poster = false,
  bool hasFile = true,
  String? added,
  String? digitalRelease,
  String? physicalRelease,
}) => RadarrMovie(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  sizeOnDisk: 0,
  status: 'released',
  hasFile: hasFile,
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
  added: added,
  digitalRelease: digitalRelease,
  physicalRelease: physicalRelease,
);

final _library = [
  _movie(
    1,
    'Nosferatu',
    1922,
    poster: true,
    added: _earlierToday(const Duration(minutes: 20)),
  ),
  _movie(
    2,
    'Metropolis',
    1927,
    hasFile: false,
    added: _earlierToday(const Duration(hours: 2)),
    digitalRelease: _inDays(1),
  ),
  _movie(
    3,
    'The Cabinet of Dr. Caligari',
    1920,
    added: _earlierToday(const Duration(hours: 3)),
    physicalRelease: _inDays(4),
  ),
  _movie(
    4,
    'Sherlock Jr.',
    1924,
    added: _earlierToday(const Duration(hours: 4)),
  ),
];

final _queue = [
  {
    'movie': {'id': 2, 'title': 'Metropolis'},
    'title': 'Metropolis.1927.1080p.BluRay.x264',
    'trackedDownloadState': 'downloading',
    'status': 'warning',
    'errorMessage': 'The download is stalled with no connections',
    'downloadClient': 'qBittorrent',
    'added': _earlierToday(const Duration(hours: 1)),
  },
  {
    'movie': {'id': 3, 'title': 'The Cabinet of Dr. Caligari'},
    'title': 'The.Cabinet.of.Dr.Caligari.1920.720p.BluRay.x264',
    'trackedDownloadState': 'importFailed',
    'errorMessage': 'No files found are eligible for import',
    'added': _earlierToday(const Duration(hours: 2)),
  },
];

final _history = [
  {
    'movie': {'title': 'Nosferatu'},
    'eventType': 'downloadFolderImported',
    'quality': {
      'quality': {'name': 'Bluray-1080p'},
    },
    'data': {'size': '8053063680'},
    'date': _earlierToday(const Duration(minutes: 20)),
  },
  {
    'movie': {'title': 'Metropolis'},
    'eventType': 'grabbed',
    'quality': {
      'quality': {'name': 'Bluray-1080p'},
    },
    'size': 10737418240,
    'date': _earlierToday(const Duration(hours: 1)),
  },
];

/// Radarr answering every section, offline.
class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({this.libraryFailure});

  /// What the library endpoint fails with, while the rest of the server
  /// answers — or null for a library that loads. A real failure, so the app's
  /// own classification decides the tone: a bare `Exception` is a failure
  /// nobody can attribute, and would paint amber where the scene means red.
  final Object? libraryFailure;

  @override
  Future<List<RadarrMovie>> getMovies() async => _library;

  @override
  Future<List<RadarrMovie>> getMoviesOrThrow() async {
    final failure = libraryFailure;
    if (failure != null) throw failure;
    return _library;
  }

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => _queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => _history;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => const ArrRecordPage(records: [], total: 3);
}

/// A Radarr that has not answered yet.
class _PendingRadarr extends FakeRadarrService {
  final _never = Completer<Never>();

  @override
  Future<List<RadarrMovie>> getMovies() => _never.future;

  @override
  Future<List<RadarrMovie>> getMoviesOrThrow() => _never.future;

  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) =>
      _never.future;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) => _never.future;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) => _never.future;
}

/// The reachability probe. An empty [version] throws (unreachable).
class _StatusClient extends ApiClient {
  _StatusClient(this.version)
    : super(baseUrl: 'https://radarr.lan:7878', apiKey: 'k');

  final String? version;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (version!.isEmpty) throw const SocketException('Connection refused');
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'version': version},
    );
  }

  @override
  void close({bool force = false}) {}
}

late SharedPreferences _prefs;

/// One scene's own root container.
///
/// A nested `ProviderScope` only replaces the providers it names: everything
/// derived from them (the Overview's sections, the identity, the readouts)
/// still resolves in the sheet's root, so each scene gets a container of its
/// own. Retry is off, so a failed source stays failed instead of flickering
/// back to loading on its backoff.
class _Isolated extends StatefulWidget {
  const _Isolated(this.overrides, this.child);

  final List<Override> overrides;
  final Widget child;

  @override
  State<_Isolated> createState() => _IsolatedState();
}

class _IsolatedState extends State<_Isolated> {
  late final _container = ProviderContainer(
    overrides: widget.overrides,
    retry: (_, _) => null,
  );

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

Widget _radarr(
  RadarrService service,
  Widget child, {
  String? version = '5.14.0',
  SettingsModel settings = _oneRadarr,
}) => _Isolated([
  sharedPreferencesProvider.overrideWithValue(_prefs),
  secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
  initialSettingsProvider.overrideWithValue(settings),
  initialOnboardingCompletedProvider.overrideWithValue(true),
  initialActiveInstancesProvider.overrideWithValue(const {}),
  radarrServiceProvider.overrideWithValue(service),
  radarrServiceForProvider.overrideWith((ref, instanceId) => service),
  // A probe still in flight. Overridden above the client rather than through
  // it: the client's timeout would leave a timer running past the sheet.
  if (version == null)
    serviceSummaryProvider.overrideWith(
      (ref, service) => Completer<ServiceSummary>().future,
    ),
  serviceStatusClientFactoryProvider.overrideWithValue(
    ({
      required String baseUrl,
      required String apiKey,
      String? pinnedCertFingerprint,
    }) => _StatusClient(version),
  ),
], child);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  catalogCard(
    'ServiceOverview',
    width: 1328,
    scenes: [
      CatalogScene(
        'RadarrOverviewScreen · loaded · identity, readouts, then Coming up, '
        'Needs attention, Recently added and History in one scroll',
        (_) => _radarr(
          _ScriptedRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 900,
      ),
      CatalogScene(
        'RadarrOverviewScreen · the library timed out · the server answers, '
        'so the failure is amber: every figure the library owns reads —, and '
        'the two sections built on it fail in their own slots while the queue '
        'and history still draw',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: DioException(
              requestOptions: RequestOptions(path: '/api/v3/movie'),
              type: DioExceptionType.receiveTimeout,
            ),
          ),
          const RadarrOverviewScreen(topPadding: 0),
        ),
        width: 390,
        height: 1180,
      ),
      CatalogScene(
        'RadarrOverviewScreen · did not answer · red, and only here: the '
        'version is —, never the v3 API fallback',
        (_) => _radarr(
          _ScriptedRadarr(
            libraryFailure: const SocketException('Connection refused'),
          ),
          const RadarrOverviewScreen(topPadding: 0),
          version: '',
        ),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'RadarrOverviewScreen · loading · Checking, row skeletons and a — '
        'count while every source is in flight',
        (_) => _radarr(
          _PendingRadarr(),
          const RadarrOverviewScreen(topPadding: 0),
          version: null,
        ),
        width: 390,
        height: 760,
      ),
      CatalogScene(
        'ServiceTabScaffold + RadarrOverviewScreen · desktop window, two '
        'connections · the lit header replaces both phone bands; the lens '
        'chip joins the identity line',
        (_) => _radarr(
          _ScriptedRadarr(),
          const ServiceTabScaffold(
            service: ServiceKey.radarr,
            tab: ServiceTab.overview,
            child: RadarrOverviewScreen(
              topPadding: kToolbarHeight + ServiceTabBar.height,
            ),
          ),
          settings: _twoRadarrs,
        ),
        width: 1280,
        height: 940,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

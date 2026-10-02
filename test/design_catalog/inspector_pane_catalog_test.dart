@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import 'catalog.dart';

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

// What the pane draws under a title is `GlobalActivityItem.subtitle`: the
// release a movie came as, and for an episode its code, its title and the
// release. The size, rate and time left live on the Activity table's Details
// cell and never in this pane.
final _queue = [
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
  _transfer(ServiceKey.lidarr, 'Diamond Jubilee', 'Cindy Lee', 0),
];

GlobalActivityItem _finished(String title, StatusTone tone) =>
    GlobalActivityItem(
      kind: GlobalActivityKind.history,
      service: ServiceKey.radarr,
      serviceType: ServiceType.movies,
      title: title,
      subtitle: '',
      status: MediaStatusInfo(labelOverride: title, toneOverride: tone),
      sortDate: DateTime.now(),
    );

final _today = PagedArrFeedState(
  feed: ActivityFeed(
    items: [
      _finished('Nosferatu · imported', StatusTone.success),
      _finished(
        'The Cabinet of Dr. Caligari · import failed',
        StatusTone.warning,
      ),
      _finished('Metropolis · grabbed', StatusTone.neutral),
    ],
    results: const [],
  ),
);

class _FixedFeed extends PagedArrFeedNotifier {
  _FixedFeed(this.fixed) : super(kinds: const [GlobalActivityKind.history]);

  final PagedArrFeedState fixed;

  @override
  PagedArrFeedState build() => fixed;
}

late SharedPreferences _prefs;

/// The pane with the Activity providers answered, in a container and a router
/// of its own (a nested `ProviderScope` would leave derived providers reading
/// the sheet's root, and the header's links need a router).
class _Pane extends StatefulWidget {
  const _Pane({
    required this.queue,
    this.offline = const [],
    this.history = const PagedArrFeedState(),
  });

  final Future<ActivityFeed> Function() queue;
  final List<ServiceKey> offline;
  final PagedArrFeedState history;

  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  late final _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(const SettingsModel()),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      globalNowItemsProvider.overrideWith((ref) => widget.queue()),
      unreachableServicesProvider.overrideWithValue(widget.offline),
      globalHistoryFeedProvider.overrideWith(() => _FixedFeed(widget.history)),
    ],
    retry: (_, _) => null,
  );

  late final _router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (_, _) => const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InspectorSplitHandle(),
            SizedBox(width: 360, child: InspectorPane()),
          ],
        ),
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
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  const width = InspectorSplitHandle.width + 360;

  catalogCard(
    'InspectorPane',
    width: 1328,
    scenes: [
      CatalogScene(
        'InspectorPane beside InspectorSplitHandle · the live queue, two '
        'services that did not answer, finished today · a stuck transfer spends '
        'its amber on the bar; the red line is only for what did not answer',
        (_) => _Pane(
          queue: () async => ActivityFeed(items: _queue, results: const []),
          offline: const [ServiceKey.sonarr, ServiceKey.prowlarr],
          history: _today,
        ),
        width: width,
        height: 600,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'InspectorPane · nothing downloading · a note, not an empty well; '
        'finished today still lists what landed',
        (_) => _Pane(
          queue: () async => const ActivityFeed.empty(),
          history: _today,
        ),
        width: width,
        height: 260,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'InspectorPane · nothing downloading from what answered · the note '
        'names the connection it could not count',
        (_) => _Pane(
          queue: () async => const ActivityFeed(
            items: [],
            results: [
              ActivityServiceResult(
                service: ServiceKey.radarr,
                items: [],
                total: 0,
                configured: true,
              ),
              ActivityServiceResult(
                service: ServiceKey.sonarr,
                instanceId: 'anime',
                label: 'Anime',
                items: [],
                configured: true,
                error: 'refused',
              ),
            ],
          ),
        ),
        width: width,
        height: 130,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'InspectorPane · loading · Reading the queue…; finished today waits '
        'until the history feed has something',
        (_) => _Pane(queue: () => Completer<ActivityFeed>().future),
        width: width,
        height: 130,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'InspectorPane · the queue could not be read · no *arr answered; the '
        'note sends you to Activity, which owns the retry',
        (_) => _Pane(
          queue: () async => const ActivityFeed(
            items: [],
            results: [
              ActivityServiceResult(
                service: ServiceKey.radarr,
                items: [],
                configured: true,
                error: 'silent',
              ),
              ActivityServiceResult(
                service: ServiceKey.sonarr,
                items: [],
                configured: true,
                error: 'silent',
              ),
            ],
          ),
        ),
        width: width,
        height: 130,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · InspectorPane, the live queue with two services that '
        'did not answer and finished today, at twice the reading size',
        (_) => _Pane(
          queue: () async => ActivityFeed(items: _queue, results: const []),
          offline: const [ServiceKey.sonarr, ServiceKey.prowlarr],
          history: _today,
        ),
        width: width,
        height: 1000,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · InspectorPane, the queue could not be read: the note '
        'that sends you to Activity',
        (_) => _Pane(
          queue: () async => const ActivityFeed(
            items: [],
            results: [
              ActivityServiceResult(
                service: ServiceKey.radarr,
                items: [],
                configured: true,
                error: 'silent',
              ),
              ActivityServiceResult(
                service: ServiceKey.sonarr,
                items: [],
                configured: true,
                error: 'silent',
              ),
            ],
          ),
        ),
        width: width,
        height: 300,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

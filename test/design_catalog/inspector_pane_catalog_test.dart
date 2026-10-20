@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart'
    show downloadAskersProvider;
import 'package:cupola/features/media/presentation/media_sources_provider.dart'
    show mediaRadarrProfilesProvider;
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/queue_title.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// The inspector beside its split handle, on the download chosen in
/// Activity's table: the only thing it ever shows. Its page is the
/// DownloadDetail card's; this sheet is the pane around it.
final _now = DateTime(2026, 10, 9, 20, 53);

const _hash = 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345601';

final _settings = settingsWithServices(const [
  ServiceKey.radarr,
  ServiceKey.qbittorrent,
  ServiceKey.jellyfin,
]);

String get _radarr => _settings.primaryOf(ServiceKey.radarr)!.id;
String get _qbittorrent => _settings.primaryOf(ServiceKey.qbittorrent)!.id;

/// Sprite Fright, stuck at 47% for three hours.
final _stuck = ServiceQueueItem(
  service: ServiceKey.radarr,
  id: '1',
  title: 'Sprite Fright',
  progress: 0.47,
  clientLabel: 'qBittorrent',
  doneBytes: 1009254400,
  totalBytes: 2147483648,
  fault: InFlightFault.stalled,
  stalledSince: _now.subtract(const Duration(hours: 3)),
  downloadId: _hash,
  clientService: ServiceKey.qbittorrent,
  instanceId: _radarr,
  clientInstanceId: _qbittorrent,
  mediaId: 3,
  tmdbId: 811631,
  posterUrl: CatalogArt.poster,
  names: const MediaNames(
    title: 'Sprite Fright',
    machineName: 'Sprite.Fright.2021.1080p.WEB',
    machineKind: MachineNameKind.release,
  ),
  queueTitle: QueueTitle(
    name: 'Sprite Fright',
    year: 2021,
    qualityProfileId: 1,
    folder: '/mnt/tank/media/movies',
    digitalRelease: _now.subtract(const Duration(hours: 6)),
  ),
);

class _Chosen extends SelectedDownload {
  @override
  DownloadSelection? build() => (instanceId: _radarr, key: _hash);
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    initialSettingsProvider.overrideWithValue(_settings),
    currentSettingsProvider.overrideWith((ref) => _settings),
    titleLightProvider.overrideWith((ref, url) async => null),
    servicesQueueProvider.overrideWith(
      (ref) async => (items: [_stuck], coverage: SourceCoverage.none),
    ),
    activityLivePollProvider.overrideWith((ref, tab) {}),
    downloadAskersProvider.overrideWith((ref) => const []),
    mediaRadarrProfilesProvider(
      _radarr,
    ).overrideWith((ref) async => {1: 'HD-1080p'}),
    stallClockProvider.overrideWithValue(() => _now),
    dashboardDecisionsProvider.overrideWithValue((
      decisions: const [],
      coverage: SourceCoverage.none,
    )),
    selectedDownloadProvider.overrideWith(_Chosen.new),
  ];
}

Widget _pane() => const SizedBox(
  height: 1100,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InspectorSplitHandle(),
      Expanded(child: InspectorPane()),
    ],
  ),
);

void main() {
  const width = InspectorSplitHandle.width + 360;

  catalogCard(
    'InspectorPane',
    overrides: _overrides,
    scenes: [
      CatalogScene(
        'InspectorPane beside InspectorSplitHandle · a stuck download chosen '
        'in the desktop\'s table: Selected download, Open its page and Close, '
        'which puts the choice down and the pane with it',
        (_) => _pane(),
        width: width,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · InspectorPane on the chosen download, its header and '
        'its page at twice the reading size',
        (_) => _pane(),
        width: width,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

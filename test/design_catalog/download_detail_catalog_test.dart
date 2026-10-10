@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart'
    show downloadAskersProvider;
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/activity/presentation/widgets/download_parts.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart'
    show mediaRadarrProfilesProvider;
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/queue_title.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

final _now = DateTime(2026, 10, 9, 20, 53);

const _hash = 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345601';

final _settings = settingsWithServices(const [
  ServiceKey.radarr,
  ServiceKey.qbittorrent,
  ServiceKey.jellyfin,
  ServiceKey.seerr,
]);

String get _radarr => _settings.primaryOf(ServiceKey.radarr)!.id;
String get _qbittorrent => _settings.primaryOf(ServiceKey.qbittorrent)!.id;

ServiceQueueItem _sprite({
  InFlightFault? fault,
  bool held = false,
  bool queued = false,
}) => ServiceQueueItem(
  service: ServiceKey.radarr,
  id: '1',
  title: 'Sprite Fright',
  progress: fault == null ? 0.62 : 0.47,
  clientLabel: 'qBittorrent',
  doneBytes: 1331439862,
  totalBytes: 2147483648,
  etaSeconds: 660,
  fault: fault,
  stalledSince: _now.subtract(const Duration(hours: 3)),
  downloadId: _hash,
  clientService: ServiceKey.qbittorrent,
  instanceId: _radarr,
  clientInstanceId: _qbittorrent,
  mediaId: 3,
  held: held,
  queued: queued,
  startsInSeconds: queued ? 360 : null,
  rateBytesPerSecond: 4404019,
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

/// Four minutes of readings, a quarter of a minute apart: the speed of an
/// evening's torrent, finding its peers.
final _trace = [
  for (final (i, mb) in const [
    2.1,
    2.6,
    2.4,
    3.3,
    3.0,
    3.8,
    3.5,
    4.4,
    3.9,
    3.7,
    4.6,
    4.1,
    4.0,
    4.5,
    4.2,
    4.2,
  ].indexed)
    (
      at: _now.add(Duration(seconds: 15 * i)),
      bytesPerSecond: (mb * 1024 * 1024).round(),
    ),
];

final _anna = SeerrRequest.fromJson({
  'id': 7,
  'status': 2,
  'type': 'movie',
  'media': {'id': 70, 'tmdbId': 811631, 'mediaType': 'movie', 'status': 3},
  'requestedBy': {'id': 2, 'displayName': 'Anna'},
});

DownloadReadout _readout(ServiceQueueItem item, {bool traced = false}) =>
    DownloadReadout(
      stand: downloadStandOf(item),
      percent: downloadPercent(item),
      progress: item.progress,
      pace: downloadPaceLine(item, now: _now),
      steps: downloadStepsOf(item, player: ServiceKey.jellyfin, now: _now),
      trace: traced ? _trace : const [],
      watched: traced ? const Duration(minutes: 4) : null,
    );

final _facts = downloadFactsOf(
  _sprite(),
  profile: 'HD-1080p',
  clientAddress: 'nas.home.arpa:8080',
);

TitleLight? _light;

/// The catalog poster's light, from the same `titleLightFromPixels` the app
/// runs, read before the sheets: the app's own read never finishes in the
/// sheet's fake time.
Future<void> _readLight() async {
  final bytes = io.File(
    'design/system/assets/Imagery/poster.jpg',
  ).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: titleLightDecodeSize,
    targetHeight: titleLightDecodeSize,
  );
  final frame = await codec.getNextFrame();
  final rgba = (await frame.image.toByteData())!;
  _light = await titleLightFromPixels([
    for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
      0xFF000000 |
          rgba.getUint8(i) << 16 |
          rgba.getUint8(i + 1) << 8 |
          rgba.getUint8(i + 2),
  ]);
}

Future<List<Override>> _overrides() async => [
  titleLightProvider.overrideWith((ref, url) async => _light),
  initialSettingsProvider.overrideWithValue(_settings),
  currentSettingsProvider.overrideWith((ref) => _settings),
];

List<Override> _page(ServiceQueueItem item) => [
  servicesQueueProvider.overrideWith(
    (ref) async => (items: [item], coverage: SourceCoverage.none),
  ),
  activityLivePollProvider.overrideWith((ref, tab) {}),
  downloadAskersProvider.overrideWith((ref) => [_anna]),
  mediaRadarrProfilesProvider(
    _radarr,
  ).overrideWith((ref) async => {1: 'HD-1080p'}),
  stallClockProvider.overrideWithValue(() => _now),
  dashboardDecisionsProvider.overrideWithValue((
    decisions: const [],
    coverage: SourceCoverage.none,
  )),
];

void main() {
  setUpAll(_readLight);
  catalogCard(
    'DownloadDetail',
    overrides: _overrides,
    scenes: [
      CatalogScene(
        'DownloadPage() · Sprite Fright: who asked, 62% Downloading and '
        'until when, the steps to Jellyfin, Open lit by the title, Stop and '
        'Remove, the facts',
        (_) => DownloadPage(instanceId: _radarr, downloadKey: _hash),
        width: 390,
        height: 1180,
        overrides: _page(_sprite()),
      ),
      CatalogScene(
        'DownloadHero() · the poster, the title, the year and who asked',
        (_) => const DownloadHero(
          title: 'Sprite Fright',
          meta: '2021 · out on digital today · Anna asked for it',
          posterUrl: CatalogArt.poster,
          icon: Icons.movie_outlined,
        ),
        width: 390,
      ),
      CatalogScene(
        'DownloadReadout() · downloading, with the speed since the page was '
        'opened under the figure on a phone',
        (_) => _readout(_sprite(), traced: true),
        width: 390,
      ),
      CatalogScene(
        'DownloadReadout() · queued: Starts in about 6 min, the step in blue',
        (_) => _readout(_sprite(queued: true)),
        width: 390,
      ),
      CatalogScene(
        'DownloadReadout() · stopped on purpose: neutral, what has arrived',
        (_) => _readout(_sprite(held: true)),
        width: 390,
      ),
      CatalogScene(
        'DownloadReadout() · stuck: amber, nothing for 3 h, the step where '
        'it stopped',
        (_) => _readout(_sprite(fault: InFlightFault.stalled)),
        width: 390,
      ),
      CatalogScene(
        'DownloadReadout() · finished and waiting for an import: the import '
        'is the step that needs you',
        (_) => _readout(_sprite(fault: InFlightFault.needsImport)),
        width: 390,
      ),
      CatalogScene(
        'DownloadFacts() · Release and Folder in the mono face, the client '
        'with its address',
        (_) => DownloadFacts(facts: _facts),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the steps one to a line, the facts stacked',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _readout(_sprite(), traced: true),
            const SizedBox(height: 16),
            DownloadFacts(facts: _facts),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Beside the list on a tablet · the steps side by side, the speed '
        'beside the figure',
        (_) => _readout(_sprite(), traced: true),
        width: 620,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/download_table.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

final _now = DateTime(2026, 10, 9, 20, 53);

ServiceQueueItem _download(
  String title, {
  required String release,
  required double progress,
  ServiceKey service = ServiceKey.radarr,
  String client = 'qBittorrent',
  ServiceKey clientService = ServiceKey.qbittorrent,
  String? connectionName,
  int? rate,
  int? eta,
  InFlightFault? fault,
  bool queued = false,
  int? startsIn,
  int? tmdbId,
  String? poster,
}) => ServiceQueueItem(
  service: service,
  id: title,
  title: title,
  progress: progress,
  clientLabel: client,
  clientService: clientService,
  instanceId: service.name,
  clientInstanceId: clientService.name,
  connectionName: connectionName,
  rateBytesPerSecond: rate,
  etaSeconds: eta,
  fault: fault,
  queued: queued,
  startsInSeconds: startsIn,
  stalledSince: _now.subtract(const Duration(hours: 3)),
  tmdbId: tmdbId,
  posterUrl: poster,
  names: MediaNames(
    title: title,
    machineName: release,
    machineKind: MachineNameKind.release,
  ),
);

final _moving = [
  _download(
    'Sprite Fright',
    release: 'Sprite.Fright.2021.1080p.WEB',
    progress: 0.62,
    rate: 4404019,
    eta: 660,
    tmdbId: 811631,
    poster: CatalogArt.poster,
  ),
  _download(
    'Elephants Dream · 2160p',
    release: 'Elephants.Dream.2006.2160p.BluRay',
    progress: 0.31,
    rate: 18874368,
    eta: 360,
    connectionName: '4K',
    client: 'SABnzbd',
    clientService: ServiceKey.sabnzbd,
  ),
  _download(
    'Cosmos Laundromat · S2 E4',
    release: 'Cosmos.Laundromat.S02E04.1080p.WEB',
    progress: 0.88,
    rate: 12687769,
    eta: 60,
    service: ServiceKey.sonarr,
  ),
  _download(
    'Big Buck Bunny',
    release: 'Big.Buck.Bunny.2008.1080p.BluRay',
    progress: 0.47,
    fault: InFlightFault.stalled,
  ),
];

final _queued = [
  _download(
    'Sintel · 2160p',
    release: 'Sintel.2010.2160p.BluRay',
    progress: 0,
    queued: true,
    startsIn: 360,
    connectionName: '4K',
    client: 'SABnzbd',
    clientService: ServiceKey.sabnzbd,
  ),
];

final _anna = SeerrRequest.fromJson({
  'id': 7,
  'status': 2,
  'type': 'movie',
  'media': {'id': 70, 'tmdbId': 811631, 'mediaType': 'movie', 'status': 3},
  'requestedBy': {'id': 2, 'displayName': 'Anna'},
});

/// The stuck one chosen, as a click leaves it.
class _Chosen extends SelectedDownload {
  @override
  DownloadSelection? build() => selectionOf(_moving.last);
}

Widget _table({bool queued = false}) => ActivitySlab(
  children: [
    if (queued)
      DownloadTable.queued(items: _queued, now: _now, requests: [_anna])
    else
      DownloadTable(items: _moving, now: _now, requests: [_anna]),
  ],
);

/// [child] in a window [width] wide, whatever the sheet's width.
Widget _window(BuildContext context, double width, Widget child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(size: Size(width, 900)),
  child: child,
);

void main() {
  catalogCard(
    'DownloadTable',
    width: 1180,
    scenes: [
      CatalogScene(
        'DownloadTable() · a full window: Title, Progress, Speed and Left, '
        'in the queue\'s order; a stuck one amber with the dash for what '
        'it cannot say',
        (context) => _window(context, 1440, _table()),
        width: 1140,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DownloadTable() · the stuck one chosen: the room\'s strong fill, '
        'the inspector beside it shows it',
        (context) => _window(context, 1440, _table()),
        width: 1140,
        platform: CatalogPlatform.desktop,
        overrides: [selectedDownloadProvider.overrideWith(_Chosen.new)],
      ),
      CatalogScene(
        'DownloadTable.queued() · Up next: no header, `Queued · starts in '
        'about 6 min` across Progress, Speed and Left',
        (context) => _window(context, 1440, _table(queued: true)),
        width: 1140,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DownloadTable() · a compact window (under 1100): Speed and Left join '
        'the line under the title',
        (context) => _window(context, 960, _table()),
        width: 880,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · a full window',
        (context) => _window(context, 1440, _table()),
        width: 1140,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

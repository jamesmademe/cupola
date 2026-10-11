@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_history_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/everyone_request_row.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/media/presentation/media_split.dart'
    show MediaPaneDownload;
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _mb = 1024 * 1024;

/// Friday 9 October 2026, 20:53: the evening the rows are drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// A download of the household's evening.
ServiceQueueItem _download(
  String title,
  String release, {
  required String id,
  double? progress,
  int? eta,
  int? rate,
  ServiceKey service = ServiceKey.radarr,
  ServiceKey? client = ServiceKey.qbittorrent,
  String clientLabel = 'qBittorrent',
  String? connectionName,
  InFlightFault? fault,
  DateTime? stalledSince,
  bool queued = false,
  bool held = false,
  int? startsIn,
  int? tmdbId,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: title,
  progress: progress,
  clientLabel: clientLabel,
  clientService: client,
  connectionName: connectionName,
  etaSeconds: eta,
  rateBytesPerSecond: rate,
  fault: fault,
  stalledSince: stalledSince,
  queued: queued,
  held: held,
  startsInSeconds: startsIn,
  tmdbId: tmdbId,
  posterUrl: CatalogArt.poster,
  names: MediaNames(
    title: title,
    machineName: release,
    machineKind: MachineNameKind.release,
  ),
);

final _sprite = _download(
  'Sprite Fright',
  'Sprite.Fright.2021.1080p.WEB',
  id: '1',
  progress: 0.62,
  eta: 660,
  rate: (4.2 * _mb).round(),
  tmdbId: 811631,
);

final _elephants = _download(
  'Elephants Dream',
  'Elephants.Dream.2006.2160p.UHD.BluRay',
  id: '2',
  progress: 0.31,
  eta: 360,
  rate: 18 * _mb,
  client: ServiceKey.sabnzbd,
  clientLabel: 'SABnzbd',
  connectionName: '4K',
);

/// Stopped on purpose, from its page.
final _stopped = _download(
  'Cosmos Laundromat · S2 E5',
  'Cosmos.Laundromat.S02E05.1080p.WEB',
  id: '9',
  progress: 0.62,
  service: ServiceKey.sonarr,
  held: true,
);

final _stuck = _download(
  'Big Buck Bunny',
  'Big.Buck.Bunny.2008.1080p.BluRay',
  id: '3',
  progress: 0.47,
  fault: InFlightFault.stalled,
  stalledSince: _now.subtract(const Duration(hours: 3)),
);

final _queued = _download(
  'Sintel',
  'Sintel.2010.2160p.UHD.BluRay',
  id: '4',
  progress: 0,
  queued: true,
  startsIn: 360,
  client: ServiceKey.sabnzbd,
  clientLabel: 'SABnzbd',
  connectionName: '4K',
);

/// A torrent nobody's arr asked for: it is its client's alone.
final _handAdded = ServiceQueueItem(
  service: ServiceKey.qbittorrent,
  id: '5',
  title: 'ubuntu-24.04.1-desktop-amd64.iso',
  progress: 0.4,
  clientLabel: 'qBittorrent',
  clientService: ServiceKey.qbittorrent,
  etaSeconds: 1500,
  rateBytesPerSecond: 6 * _mb,
);

/// Anna's request for the movie [_sprite] is the download of.
const _annaAsked = SeerrRequest(
  id: 7,
  status: RequestStatus.approved,
  type: 'movie',
  createdAt: '2026-10-09T18:40:00.000Z',
  media: RequestMedia(id: 7, tmdbId: 811631, mediaType: 'movie'),
  requestedBy: RequestedBy(id: 2, displayName: 'Anna'),
);

ArrHistoryEntry _entry(
  String title, {
  required int id,
  required ArrImportOutcome outcome,
  required DateTime at,
  String? fileName,
  String? reason,
  String? connectionName,
  ServiceKey service = ServiceKey.radarr,
}) => ArrHistoryEntry(
  service: service,
  id: id,
  mediaId: id,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: CatalogArt.poster,
  outcome: outcome,
  at: at,
  reason: reason,
  connectionName: connectionName,
  fileName: fileName,
);

/// Rows on the slab they sit on in Activity.
/// One of the household's requests at [stage], asked by [who].
MyRequest _asked(
  String title,
  MyRequestStage stage, {
  required int id,
  String who = 'Anna',
  double? progress,
  Duration? readyIn,
  Duration? arrived,
  Duration? answered,
}) => MyRequest(
  request: SeerrRequest(
    id: id,
    status: RequestStatus.approved,
    type: 'movie',
    createdAt: '2026-10-01T18:40:00.000Z',
    media: RequestMedia(
      id: id,
      tmdbId: 1000 + id,
      mediaType: 'movie',
      title: title,
      posterPath: CatalogArt.tmdbPoster,
    ),
    requestedBy: RequestedBy(id: 2, displayName: who),
  ),
  stage: stage,
  progress: progress,
  readyAround: readyIn == null ? null : _now.add(readyIn),
  arrivedAt: arrived == null ? null : _now.subtract(arrived),
  answeredAt: answered == null ? null : _now.subtract(answered),
);

Widget _slab(List<Widget> rows) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: ActivitySlab(children: rows),
);

void main() {
  catalogCard(
    'ActivityRows',
    scenes: [
      CatalogScene(
        'ActivityDownloadRow() · moving: the art, the title and the release '
        'in the machine\'s face, which way the bytes go, how far and how '
        'long, how fast, and whose request brought it',
        (_) => _slab([
          ActivityDownloadRow(item: _sprite, now: _now, request: _annaAsked),
        ]),
        width: 390,
      ),
      CatalogScene(
        'ActivityDownloadRow() · two moving rows on one slab: a second '
        'connection of the arr is named, a hairline between them',
        (_) => _slab([
          ActivityDownloadRow(item: _sprite, now: _now, request: _annaAsked),
          ActivityDownloadRow(item: _elephants, now: _now, divided: true),
        ]),
        width: 390,
      ),
      CatalogScene(
        'ActivityDownloadRow() · selected: its page is open beside the list '
        "on a tablet, and the row sits on the room's strong fill",
        (_) => SidePaneScope(
          selected: MediaPaneDownload.selectedFor('1'),
          location: '/activity/downloads',
          child: _slab([
            ActivityDownloadRow(item: _sprite, now: _now, request: _annaAsked),
            ActivityDownloadRow(item: _elephants, now: _now, divided: true),
          ]),
        ),
        width: 440,
      ),
      CatalogScene(
        'ActivityDownloadRow() · stuck: Stuck at 47% in amber, and the '
        'proof, nothing for 3 h, where the speed would be',
        (_) => _slab([ActivityDownloadRow(item: _stuck, now: _now)]),
        width: 390,
      ),
      CatalogScene(
        'ActivityDownloadRow() · stopped on purpose, on Downloads after the '
        'rest: Stopped at 62% in the neutral, no speed',
        (_) => _slab([ActivityDownloadRow(item: _stopped, now: _now)]),
        width: 390,
      ),
      CatalogScene(
        'ActivityDownloadRow.queued() · in Up next: Queued · starts in '
        'about 6 min in blue, which way it will travel',
        (_) => _slab([
          ActivityDownloadRow.queued(
            item: _queued,
            now: _now,
            request: _annaAsked,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'ActivityDownloadRow() · a transfer no arr asked for: its client '
        'alone is the route, no request under it',
        (_) => _slab([ActivityDownloadRow(item: _handAdded, now: _now)]),
        width: 390,
      ),
      CatalogScene(
        'ActivityHistoryRow() · imported, in green, with the file it became '
        'in the machine\'s face; the arr and its connection at the end',
        (_) => _slab([
          ActivityHistoryRow(
            entry: _entry(
              'Spring',
              id: 1,
              outcome: ArrImportOutcome.imported,
              at: _now.subtract(const Duration(hours: 2)),
              fileName: 'Spring (2019).mkv',
              connectionName: '4K',
            ),
          ),
          ActivityHistoryRow(
            entry: _entry(
              'Coffee Run',
              id: 2,
              outcome: ArrImportOutcome.imported,
              at: _now.subtract(const Duration(hours: 4)),
              fileName: 'Coffee Run (2020).mkv',
            ),
            divided: true,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'ActivityHistoryRow() · a download that failed, in amber, with why',
        (_) => _slab([
          ActivityHistoryRow(
            entry: _entry(
              'Tears of Steel',
              id: 3,
              outcome: ArrImportOutcome.failed,
              at: _now.subtract(const Duration(hours: 7)),
              reason: 'Unable to parse file',
            ),
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · a moving row and a stuck row: the route and the '
        'figure each take a line, the title keeps its lines',
        (_) => _slab([
          ActivityDownloadRow(item: _sprite, now: _now, request: _annaAsked),
          ActivityDownloadRow(item: _stuck, now: _now, divided: true),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · Up next and the client\'s own row',
        (_) => _slab([
          ActivityDownloadRow.queued(item: _queued, now: _now),
          ActivityDownloadRow(item: _handAdded, now: _now, divided: true),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · an import with its file and a failure with its '
        'reason',
        (_) => _slab([
          ActivityHistoryRow(
            entry: _entry(
              'Spring',
              id: 1,
              outcome: ArrImportOutcome.imported,
              at: _now.subtract(const Duration(hours: 2)),
              fileName: 'Spring (2019).mkv',
              connectionName: '4K',
            ),
          ),
          ActivityHistoryRow(
            entry: _entry(
              'Tears of Steel',
              id: 3,
              outcome: ArrImportOutcome.failed,
              at: _now.subtract(const Duration(hours: 7)),
              reason: 'Unable to parse file',
            ),
            divided: true,
          ),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'EveryoneRequestRow() · the household\'s requests on the Requests '
        'view: where each stands and when in its tone, who asked at the end; '
        'blue on its way, green on the server, neutral a no, amber one that '
        'did not go through',
        (_) => _slab([
          EveryoneRequestRow(
            mine: _asked(
              'Sprite Fright',
              MyRequestStage.downloading,
              id: 1,
              progress: 0.62,
              readyIn: const Duration(minutes: 17),
            ),
            now: _now,
            divided: false,
          ),
          EveryoneRequestRow(
            mine: _asked(
              'Coffee Run',
              MyRequestStage.readyToWatch,
              id: 2,
              arrived: const Duration(hours: 2, minutes: 13),
            ),
            now: _now,
            divided: true,
          ),
          EveryoneRequestRow(
            mine: _asked(
              'Metropolis',
              MyRequestStage.declined,
              id: 3,
              who: 'Luca',
              answered: const Duration(days: 1),
            ),
            now: _now,
            divided: true,
          ),
          EveryoneRequestRow(
            mine: _asked(
              'Cosmos Laundromat',
              MyRequestStage.didNotGoThrough,
              id: 4,
              answered: const Duration(days: 3),
            ),
            now: _now,
            divided: true,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'EveryoneRequestRow(connection:) · a list that holds two Seerrs names '
        'each row\'s under its state; at 200% the lines wrap, none cut',
        (_) => _slab([
          EveryoneRequestRow(
            mine: _asked(
              'Tears of Steel',
              MyRequestStage.onTheServer,
              id: 5,
              arrived: const Duration(days: 27),
            ),
            now: _now,
            divided: false,
            connection: 'Seerr Cabin',
          ),
          EveryoneRequestRow(
            mine: _asked('Sintel', MyRequestStage.onItsWay, id: 6, who: 'Luca'),
            now: _now,
            divided: true,
            connection: 'Seerr Home',
          ),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'On the desktop · downloads and what finished on one slab in the '
        'page well',
        (_) => _slab([
          ActivityDownloadRow(item: _sprite, now: _now, request: _annaAsked),
          ActivityDownloadRow(item: _stuck, now: _now, divided: true),
          ActivityHistoryRow(
            entry: _entry(
              'Spring',
              id: 1,
              outcome: ArrImportOutcome.imported,
              at: _now.subtract(const Duration(hours: 2)),
              fileName: 'Spring (2019).mkv',
            ),
            divided: true,
          ),
        ]),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}

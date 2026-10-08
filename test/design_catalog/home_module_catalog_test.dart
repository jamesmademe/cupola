@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/home/presentation/widgets/set_up_next_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

final _now = DateTime(2026, 9, 29, 20, 53);

DashboardDecision _fault(
  DecisionKind kind,
  String title, {
  int count = 1,
  ServiceKey service = ServiceKey.radarr,
}) => DashboardDecision(
  kind: kind,
  id: '${kind.name}-$title',
  service: service,
  title: title,
  detail: '',
  occurredAt: null,
  count: count,
);

NeedsYou _needs({
  List<ServiceKey> silent = const [],
  required List<DashboardDecision> decisions,
}) => needsYouOf(
  silent: silent,
  decisions: decisions,
  now: _now,
  silentAt: _now,
)!;

ServiceQueueItem _download(
  String title,
  String release, {
  required String id,
  double? progress,
  int? eta,
  InFlightFault? fault,
  ServiceKey service = ServiceKey.radarr,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: title,
  progress: progress,
  clientLabel: 'qBittorrent',
  etaSeconds: eta,
  fault: fault,
  clientService: ServiceKey.qbittorrent,
  posterUrl: CatalogArt.poster,
  names: MediaNames(
    title: title,
    machineName: release,
    machineKind: MachineNameKind.release,
  ),
);

/// Three moving and one stuck, as the household's evening has them.
final _evening = (
  preview: [
    _download(
      'Cosmos Laundromat · S2 E4',
      'Cosmos.Laundromat.S02E04.1080p.WEB',
      id: '1',
      progress: 0.88,
      eta: 60,
      service: ServiceKey.sonarr,
    ),
    _download(
      'Sprite Fright',
      'Sprite.Fright.2021.1080p.WEB',
      id: '2',
      progress: 0.62,
      eta: 660,
    ),
    _download(
      'Elephants Dream',
      'Elephants.Dream.2006.2160p.BluRay',
      id: '3',
      progress: 0.31,
      eta: 360,
    ),
  ],
  activeCount: 3,
  faults: [
    _download(
      'Big Buck Bunny',
      'Big.Buck.Bunny.2008.1080p.BluRay',
      id: '4',
      progress: 0.47,
      fault: InFlightFault.stalled,
    ),
  ],
  held: 0,
  rateBytesPerSecond: 40400000,
  clients: 2,
  coverage: SourceCoverage.none,
);

final _noHistory = (
  entries: const <ArrHistoryEntry>[],
  coverage: SourceCoverage.none,
);

final _clientSettings = settingsWithServices(const [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.seerr,
  ServiceKey.qbittorrent,
  ServiceKey.jellyfin,
]);

DashboardDecision _request(String title, int id, String detail, int hours) =>
    DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'seerr--$id',
      service: ServiceKey.seerr,
      title: title,
      detail: detail,
      // The row says when against the clock it is drawn on.
      occurredAt: DateTime.now().subtract(Duration(hours: hours)),
      actionId: id,
      posterUrl: CatalogArt.poster,
    );

class _Answered extends AnsweredRequests {
  _Answered(this.initial);

  final Map<String, AnsweredRequest> initial;

  @override
  Map<String, AnsweredRequest> build() => initial;
}

StreamActivityRow _playing(
  String user,
  String title,
  String device,
  int minutesLeft,
  double progress, {
  String? subtitle,
  bool paused = false,
}) => (
  service: ServiceKey.jellyfin,
  instanceId: '',
  connectionName: null,
  session: StreamSession(
    id: '$user-$title',
    userName: user,
    title: title,
    subtitle: subtitle,
    deviceLabel: device,
    posterPath: null,
    playMethod: StreamPlayMethod.directPlay,
    transcodeReasons: const [],
    bitrate: null,
    bitrateIsNominal: true,
    progress: progress,
    isPaused: paused,
    remaining: Duration(minutes: minutesLeft),
  ),
);

/// Rows standing in for a module's own: the frame does not own them.
class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, (title, line)) in rows.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index > 0
                  ? Border(top: BorderSide(color: room.hair))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.row.copyWith(color: room.ink)),
                  Text(
                    line,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void main() {
  catalogCard(
    'HomeModule',
    width: 840,
    overrides: () async => settingsScopeOverrides(
      configured: const [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.seerr,
      ],
    ),
    scenes: [
      CatalogScene(
        'HomeModuleFrame · ready: the name, the line under it, the rows in '
        'the slab',
        (_) => const HomeModuleFrame(
          title: 'Requests',
          subtitle: '2 wait for you',
          child: _Rows([
            ('Charge', 'Anna · 2 h ago'),
            ('Metropolis', 'Luca · yesterday'),
          ]),
        ),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.loading · the name over the shape of its rows, never '
        'a spinner',
        (_) => const HomeModuleFrame.loading(title: 'Downloads'),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.silent · its sources did not answer: it keeps its '
        'place and names the service, with Retry',
        (_) => HomeModuleFrame.silent(
          title: 'Arrived',
          coverage: SourceCoverage.failure(
            ServiceKey.radarr,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
          onRetry: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.needsService · switched on in Edit Home without its '
        'service: dimmed, a target, the service named',
        (_) => HomeModuleFrame.needsService(
          title: 'Storage',
          service: ServiceKey.truenas,
          setUpLine: 'Pools, space and disk health',
          onSetUp: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · the largest group of equal faults leads, two more '
        'things wait, Review',
        (_) => NeedsYouLine(
          needs: _needs(
            decisions: [
              _fault(DecisionKind.stalledDownload, 'Big Buck Bunny'),
              _fault(
                DecisionKind.importBlocked,
                'Cosmos Laundromat',
                count: 18,
                service: ServiceKey.sonarr,
              ),
              _fault(DecisionKind.stoppedStack, 'media'),
            ],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · one fault: no count',
        (_) => NeedsYouLine(
          needs: _needs(
            decisions: [_fault(DecisionKind.stalledDownload, 'Big Buck Bunny')],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · a service that did not answer leads, in red, with its '
        'time and Retry',
        (_) => NeedsYouLine(
          needs: _needs(
            silent: const [ServiceKey.radarr],
            decisions: [
              _fault(DecisionKind.importBlocked, 'x', count: 18),
              _fault(DecisionKind.stalledDownload, 'Big Buck Bunny'),
              _fault(DecisionKind.stoppedStack, 'media'),
            ],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Set up next · Radarr, Sonarr and Seerr set up: what each missing '
        'service adds, then All services',
        (_) => const SetUpNextModule(),
        width: 390,
      ),
      CatalogScene(
        'Downloads · what moves, how far and how long; the stuck one in '
        'amber with Try another download and More',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith((ref) async => _evening),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'Downloads · qBittorrent did not answer: the speed is a dash, the '
        'rows keep what the arrs know',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith(
            (ref) async => (
              preview: _evening.preview,
              activeCount: 3,
              faults: const <ServiceQueueItem>[],
              held: 0,
              rateBytesPerSecond: null,
              clients: 0,
              coverage: SourceCoverage.merge([
                SourceCoverage.answeredBy(ServiceKey.radarr),
                SourceCoverage.failure(
                  ServiceKey.qbittorrent,
                  const ClassifiedFailure(ServiceFailureReason.unreachable),
                ),
              ]),
            ),
          ),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'Downloads · nothing moving: a calm line and when the last download '
        'finished',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith(
            (ref) async => (
              preview: const <ServiceQueueItem>[],
              activeCount: 0,
              faults: const <ServiceQueueItem>[],
              held: 0,
              rateBytesPerSecond: 0,
              clients: 1,
              coverage: SourceCoverage.none,
            ),
          ),
          servicesArrHistoryProvider.overrideWith(
            (ref) async => (
              entries: [
                ArrHistoryEntry(
                  service: ServiceKey.radarr,
                  id: 1,
                  mediaId: 1,
                  title: 'Spring',
                  unitId: null,
                  detail: '',
                  posterUrl: '',
                  outcome: ArrImportOutcome.imported,
                  at: DateTime.now().subtract(const Duration(days: 1)),
                  reason: null,
                ),
              ],
              coverage: SourceCoverage.none,
            ),
          ),
        ],
      ),
      CatalogScene(
        'Requests · Charge approved here keeps its row, saying where it went; '
        'Metropolis still waits with Approve and Decline',
        (_) => const HomeRequestsModule(),
        width: 390,
        overrides: [
          dashboardDecisionSourceProvider.overrideWith(
            (ref, source) async => (
              decisions: [_request('Metropolis', 2, 'Luca', 20)],
              coverage: SourceCoverage.none,
            ),
          ),
          pendingRequestCountProvider.overrideWith(
            (ref) async => (count: 1, floor: false),
          ),
          answeredRequestsProvider.overrideWith(
            () => _Answered({
              'seerr--1': (
                decision: _request('Charge', 1, 'Anna', 2),
                outcome: 'Approved · sent to Radarr',
              ),
            }),
          ),
        ],
      ),
      CatalogScene(
        'Now playing · who, what, on which screen and how long is left, over '
        'an ink bar',
        (_) => const HomeNowPlayingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          streamActivityProvider.overrideWith(
            (ref) async => [
              _playing('Anna', 'Sintel', 'Living room TV', 9, 0.4),
              _playing(
                'Luca',
                'Cosmos Laundromat',
                'Infuse · iPhone',
                5,
                0.8,
                subtitle: 'S2 E3 · The Second Cycle',
                paused: true,
              ),
            ],
          ),
          streamActivityOfflineProvider.overrideWith(
            (ref) async => const <StreamOfflineSource>[],
          ),
        ],
      ),
      CatalogScene(
        'EditHomeRow · the way to Edit Home, at the foot of the operator\'s '
        'Home',
        (_) => const EditHomeRow(),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · Needs you, Set up next and Downloads wrap and keep '
        'their targets',
        (_) => Column(
          children: [
            NeedsYouLine(
              needs: _needs(
                decisions: [
                  _fault(DecisionKind.importBlocked, 'x', count: 18),
                  _fault(DecisionKind.stoppedStack, 'media'),
                ],
              ),
              onTap: () {},
            ),
            const SetUpNextModule(),
            const HomeDownloadsModule(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith((ref) async => _evening),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
    ],
  );
}

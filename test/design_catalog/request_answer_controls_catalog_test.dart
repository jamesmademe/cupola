@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/approve_request_sheet.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/requests/presentation/widgets/request_answer_controls.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

class _InFlight extends RequestAnswersInFlight {
  _InFlight(this.initial);

  final Map<RequestAnswerKey, RequestAnswerPhase> initial;

  @override
  Map<RequestAnswerKey, RequestAnswerPhase> build() => initial;
}

class _Answered extends AnsweredRequests {
  _Answered(this.initial);

  final Map<String, AnsweredRequest> initial;

  @override
  Map<String, AnsweredRequest> build() => initial;
}

/// An account of the operator's that may ask and nothing more: the pair is
/// drawn, dimmed, and says why when it is pressed.
final _mayNotApprove = roleGateProvider('').overrideWithValue(
  RoleGate(
    audience: Audience.operator,
    grant: const SeerrGrant.account(permissions: 32),
    server: SeerrServerFacts.fromPublicSettings({
      'mediaServerType': 2,
      'localLogin': true,
    }),
  ),
);

/// A request's words on a slab, and the control under them as the surface
/// sets it.
class _Slab extends StatelessWidget {
  const _Slab({
    required this.title,
    required this.detail,
    required this.control,
  });

  final String title;
  final String detail;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: room.slab,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: room.hair),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppType.row
                    .weight(FontWeight.w600)
                    .copyWith(color: room.ink),
              ),
              Text(
                detail,
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
              const SizedBox(height: 8),
              control,
            ],
          ),
        ),
      ),
    );
  }
}

/// A request of the lens's Seerr, by its id there.
Widget _row(int id, String title, String detail) => _Slab(
  title: title,
  detail: detail,
  control: RequestAnswerControls.row(
    instanceId: '',
    requestId: id,
    title: title,
  ),
);

void main() {
  catalogCard(
    'RequestAnswerControls',
    width: 840,
    overrides: () async =>
        settingsScopeOverrides(configured: const [ServiceKey.seerr]),
    scenes: [
      CatalogScene(
        'RequestAnswerControls.row · idle (Charge); Approve busy while the '
        'server it goes to is read (Metropolis), the other button waiting; '
        'Decline busy while it is sent (Sprite Fright)',
        (_) => Column(
          children: [
            _row(1, 'Charge', 'Anna · 2 h ago · Standard'),
            _row(2, 'Metropolis', 'Luca · yesterday · Standard'),
            _row(3, 'Sprite Fright', 'Anna · Tue 6 Oct · Standard'),
          ],
        ),
        width: 390,
        overrides: [
          requestAnswersInFlightProvider.overrideWith(
            () => _InFlight({
              (instanceId: '', requestId: 2): RequestAnswerPhase.checking,
              (instanceId: '', requestId: 3): RequestAnswerPhase.declining,
            }),
          ),
        ],
      ),
      CatalogScene(
        'RequestAnswerControls.row · answered: the pair gives way to where '
        'the request went (`Approved · sent to Radarr`), or `Declined`',
        (_) => Column(
          children: [
            _row(1, 'Charge', 'Anna · 2 h ago · Standard'),
            _row(2, 'Metropolis', 'Luca · yesterday · Standard'),
          ],
        ),
        width: 390,
        overrides: [
          answeredRequestsProvider.overrideWith(
            () => _Answered({
              'seerr--1': (
                decision: null,
                outcome: 'Approved · sent to Radarr',
              ),
              'seerr--2': (decision: null, outcome: 'Declined'),
            }),
          ),
        ],
      ),
      CatalogScene(
        'RequestAnswerControls.row · an account that may not approve keeps '
        'the pair, dimmed, and says why when it is pressed',
        (_) => _row(1, 'Charge', 'Anna · 2 h ago · Standard'),
        width: 390,
        overrides: [_mayNotApprove],
      ),
      CatalogScene(
        'RequestAnswerControls.row · text at 200%, a long title: the pair '
        'goes one under the other when a verb would not fit, and busy keeps '
        'its place',
        (_) => Column(
          children: [
            _row(
              1,
              'The Lord of the Rings: The Fellowship of the Ring',
              'Konstantinos · 2 h ago · Standard',
            ),
            _row(2, 'Dune', 'Ada · yesterday · Standard'),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          requestAnswersInFlightProvider.overrideWith(
            () => _InFlight({
              (instanceId: '', requestId: 2): RequestAnswerPhase.approving,
            }),
          ),
        ],
      ),
      CatalogScene(
        'RequestAnswerControls.card · stacked on a title\'s page, Approve '
        'with its glyph: in ink where the card leads the page, quiet under a '
        'lead that plays; busy while it is sent',
        (context) {
          final room = CupolaRoom.of(context);
          return Column(
            children: [
              _Slab(
                title: 'Anna asked for it',
                detail: 'Waiting for approval · 2 h ago',
                control: RequestAnswerControls.card(
                  instanceId: '',
                  requestId: 1,
                  title: 'Charge',
                  approveStyle: mediaLeadStyle(context, null),
                ),
              ),
              _Slab(
                title: 'Luca asked for it',
                detail: 'Waiting for approval · yesterday',
                control: RequestAnswerControls.card(
                  instanceId: '',
                  requestId: 2,
                  title: 'Metropolis',
                  approveStyle: FilledButton.styleFrom(
                    backgroundColor: room.fillStrong,
                    foregroundColor: room.ink,
                  ),
                ),
              ),
            ],
          );
        },
        width: 390,
        overrides: [
          requestAnswersInFlightProvider.overrideWith(
            () => _InFlight({
              (instanceId: '', requestId: 2): RequestAnswerPhase.approving,
            }),
          ),
        ],
      ),
      CatalogScene(
        'Approve sheet · where Charge goes, with another Radarr of its copy '
        'to send it to, the quality profile and the root folder',
        (_) => const Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomSheet(
            title: 'Approve Charge',
            subtitle: 'Anna asked${dotSeparator}Standard',
            showClose: true,
            child: ApproveRequestBody(
              instanceId: '',
              title: 'Charge',
              request: _approved,
              target: _approveTarget,
              servers: [_radarr, _spare],
              connections: [],
              connectionTitle: _serviceTitle,
            ),
          ),
        ),
        width: 390,
        height: 620,
        overrides: [
          seerrServerChoicesProvider.overrideWith(
            (ref, source) async => (
              profiles: const [
                QualityProfileOption(id: 4, name: 'HD-1080p'),
                QualityProfileOption(id: 6, name: 'Ultra-HD'),
              ],
              folders: const [
                RootFolderOption(
                  path: '/mnt/tank/media/movies',
                  freeSpace: 12400000000000,
                ),
                RootFolderOption(path: '/mnt/tank/media/spare'),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

const _radarr = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 0,
  name: 'Radarr',
  isDefault: true,
  activeProfileId: 4,
  activeProfileName: 'HD-1080p',
  activeDirectory: '/mnt/tank/media/movies',
);
const _spare = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 2,
  name: 'Radarr spare',
  activeProfileId: 6,
  activeDirectory: '/mnt/tank/media/spare',
);
const _approved = SeerrRequest(
  id: 1,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-10-21T10:00:00Z',
  type: 'movie',
);
const _approveTarget = SeerrApproveTarget(
  arr: ServiceKey.radarr,
  is4k: false,
  serversRead: true,
  server: _radarr,
  profileId: 4,
  rootFolder: '/mnt/tank/media/movies',
);

String _serviceTitle(ServiceInstance connection) => connection.service.title;

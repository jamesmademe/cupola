@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/requests/presentation/widgets/request_answer_controls.dart';
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

/// The dense row of a desktop table: the title, the pair, a status.
class _Strip extends StatelessWidget {
  const _Strip({required this.id, required this.title});

  final int id;
  final String title;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: room.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTheme.chrome(
                context,
                size: 14,
                weight: FontWeight.w600,
                color: room.ink,
              ),
            ),
          ),
          RequestAnswerControls.compact(
            instanceId: '',
            requestId: id,
            title: title,
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 72,
            child: Text(
              'Pending',
              textAlign: TextAlign.end,
              style: AppTheme.chrome(
                context,
                size: 11,
                color: room.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        'stays whole, and busy keeps its place',
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
        'RequestAnswerControls.compact · a desktop table row: idle (Charge), '
        'Approve busy (Metropolis), Decline busy (Sprite Fright), answered '
        '(Spring, Tears of Steel)',
        (_) => const Column(
          children: [
            _Strip(id: 1, title: 'Charge'),
            _Strip(id: 2, title: 'Metropolis'),
            _Strip(id: 3, title: 'Sprite Fright'),
            _Strip(id: 4, title: 'Spring'),
            _Strip(id: 5, title: 'Tears of Steel'),
          ],
        ),
        width: 840,
        platform: CatalogPlatform.desktop,
        overrides: [
          requestAnswersInFlightProvider.overrideWith(
            () => _InFlight({
              (instanceId: '', requestId: 2): RequestAnswerPhase.checking,
              (instanceId: '', requestId: 3): RequestAnswerPhase.declining,
            }),
          ),
          answeredRequestsProvider.overrideWith(
            () => _Answered({
              'seerr--4': (
                decision: null,
                outcome: 'Approved · sent to Radarr',
              ),
              'seerr--5': (decision: null, outcome: 'Declined'),
            }),
          ),
        ],
      ),
      CatalogScene(
        'RequestAnswerControls.compact · an account that may not approve: '
        'dimmed, and it says why when pressed',
        (_) => const _Strip(id: 1, title: 'Charge'),
        width: 840,
        platform: CatalogPlatform.desktop,
        overrides: [_mayNotApprove],
      ),
    ],
  );
}

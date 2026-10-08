@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/home/presentation/widgets/set_up_next_module.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
        'EditHomeRow · the way to Edit Home, at the foot of the operator\'s '
        'Home',
        (_) => const EditHomeRow(),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the frame, Needs you and Set up next wrap and keep '
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
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}

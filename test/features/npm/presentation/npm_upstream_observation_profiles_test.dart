/// From a phone away from home, every proxy host that forwards to a LAN name
/// fails the upstream probe, which runs from this device and not from NPM.
///
/// The Overview used to head Needs attention with "Upstream down" for each of
/// them, in amber: a fault stated about hosts that may be fine. The probe now
/// says what it saw and from where, on the host's own row, and Needs attention
/// lists only what NPM itself declared.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/npm/data/npm_upstream_probe.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('P3 with an NPM, away: a LAN upstream this device could not '
      'reach is said as that, and is not a fault', (tester) async {
    final profile = Profiles.p3.withConnection(WorldConnections.npm);
    final harness = await ProfileHarness.start(
      profile,
      overrides: [
        // The probe opens raw sockets, which the fake network cannot answer:
        // its verdict is set here, as a phone away from home finds it.
        npmUpstreamReportProvider.overrideWith(
          (ref) async => NpmUpstreamReport(
            byHostId: const {1: NpmUpstream.down},
            checked: 1,
            total: 1,
            takenAt: DateTime(2026, 10, 2),
          ),
        ),
      ],
    );
    harness.network.on(
      'npm',
      'GET',
      '/api/nginx/proxy-hosts',
      (_) => NetworkReply.json([
        {
          'id': 1,
          'domain_names': ['photos.example.net'],
          'forward_scheme': 'http',
          'forward_host': 'immich.lan',
          'forward_port': 2283,
          'enabled': true,
          'meta': {'nginx_online': true},
        },
      ]),
    );
    await tester.binding.setSurfaceSize(const Size(430, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    harness.network.followFakeTime(tester.binding);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: NpmOverviewScreen(topPadding: 0)),
        ),
      ),
    );
    await harness.settle(tester);

    expect(find.textContaining('Upstream down'), findsNothing);
    expect(
      tester
          .widget<SectionHeader>(
            find.widgetWithText(SectionHeader, 'Needs attention'),
          )
          .subtitle,
      // No fault, and a count of none is not drawn under the heading.
      isNull,
    );
    expect(
      find.textContaining(
        'http://immich.lan:2283\u00A0· serving\u00A0· not reachable from this device',
      ),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });
}

/// Something other than the service answers at its address, and the app says
/// so: on the Dashboard, on the service's library and in its connection test.
///
/// The case behind "Radarr and Sonarr answering, with empty libraries": a web
/// page (a proxy's default page, an address missing its base path) answered
/// every request with a 200, the probe called any 2xx answering, and every
/// list read turned the page into `[]`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ServiceSummary> _probe(
  ConfigProfile profile,
  ServiceKey service,
  String id,
) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container(retry: (_, _) => null);
  return container.read(
    instanceSummaryProvider((service: service, instanceId: id)).future,
  );
}

Color _amber() {
  final scheme = AppTheme.darkTheme().colorScheme;
  return statusToneColor(scheme, StatusTone.warning);
}

void main() {
  group('a web page answering for an arr', () {
    test('is a fault on the probe, never answering', () async {
      final summary = await _probe(
        Profiles.p1.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.servesHtmlPage,
        ),
        ServiceKey.radarr,
        WorldIds.radarr,
      );

      expect(summary.isOnline, isFalse);
      expect(summary.status, ServiceSummaryStatus.fault);
    });

    final libraries = <(String, ServiceKey, String, Widget)>[
      (
        'Radarr',
        ServiceKey.radarr,
        WorldIds.radarr,
        const MoviesScreen(showAppBar: false),
      ),
      (
        'Sonarr',
        ServiceKey.sonarr,
        WorldIds.sonarr,
        const SeriesScreen(showAppBar: false),
      ),
      (
        'Lidarr',
        ServiceKey.lidarr,
        WorldIds.lidarr,
        const MusicScreen(showAppBar: false),
      ),
    ];

    for (final (name, service, id, screen) in libraries) {
      testWidgets('the $name library says what answered, not that it is '
          'empty', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(id, ConnectionBehaviour.servesHtmlPage),
          child: screen,
        );

        expect(find.byType(ServiceOfflineState), findsOneWidget);
        expect(find.text(describeUnreadable(service)), findsOneWidget);
        expect(find.text('No items found'), findsNothing);
        final glyph = tester.widget<Icon>(
          find
              .descendant(
                of: find.byType(ServiceOfflineState),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(glyph.color, _amber());
        expect(
          find.textContaining('A web page answered at nas.home.arpa:'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });
    }
  });
}

/// The headline the classification gives an answer nobody can read.
String describeUnreadable(ServiceKey service) => failureHeadline(
  ServiceFailureReason.invalidResponse,
  subject: service.title,
);

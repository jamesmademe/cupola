import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/service_room_light.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/stream_session_poster.dart';

import '../../test_helpers/settings_scope.dart';

const _sintel = 'https://image.tmdb.org/t/p/original/sintel.jpg';
const _cosmos = 'https://artworks.thetvdb.com/cosmos.jpg';

StreamSession _session(String id, String title, String titleId) =>
    StreamSession(
      id: id,
      userName: 'Anna',
      title: title,
      subtitle: null,
      deviceLabel: 'Living room TV',
      posterPath: null,
      playMethod: StreamPlayMethod.directPlay,
      transcodeReasons: const [],
      bitrate: null,
      bitrateIsNominal: true,
      progress: 0.4,
      isPaused: false,
      titleId: titleId,
    );

/// A media server's room says what is playing three times: the figure in its
/// head, its Now playing, and its light. They used to read two caches of the
/// same `/Sessions` (the figure a "strict" twin), and only Now playing's was
/// read again by the Home's poll, so the room could say `1 stream` over a
/// list that had moved on until it was pulled. One read now feeds all three,
/// and the room reads it again while it is seen.
void main() {
  testWidgets('the figure, Now playing and the light follow the sessions '
      'while the Overview is seen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var playing = [_session('s1', 'Sintel', 'jf-sintel')];
    var reads = 0;

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              jellyfinUrl: 'http://jelly.lan:8096',
              jellyfinApiKey: 'key',
              jellyfinUserId: 'viewer-1',
            ),
          ),
          jellyfinSessionsProvider.overrideWith((ref) async {
            reads++;
            return playing;
          }),
          jellyfinLibrariesProvider.overrideWith((ref) async => const []),
          jellyfinStrictLibrariesProvider.overrideWith((ref) async => const []),
          streamSessionPosterProvider.overrideWith(
            (ref, title) async => switch (title.titleId) {
              'jf-sintel' => _sintel,
              'jf-cosmos' => _cosmos,
              _ => null,
            },
          ),
          serviceSummaryProvider.overrideWith(
            (ref, key) async => ServiceSummary(
              service: key,
              status: ServiceSummaryStatus.online,
              host: 'media.lan',
              version: '10.10.6',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          themeAnimationDuration: Duration.zero,
          home: const StreamOverviewScreen(
            service: ServiceKey.jellyfin,
            topPadding: 0,
          ),
        ),
      ),
    );
    await _settle(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StreamOverviewScreen)),
    );
    final light = container.listen(
      serviceRoomSourceProvider(ServiceKey.jellyfin),
      (_, _) {},
    );
    addTearDown(light.close);
    await _settle(tester);

    String? streams() => container
        .read(serviceKpiProvider(ServiceKey.jellyfin))
        .value
        ?.firstWhere((kpi) => kpi.label == 'Streams')
        .value;

    expect(reads, 1, reason: 'the figure and the list share one read');
    expect(streams(), '1');
    expect(find.textContaining('Sintel'), findsOneWidget);
    expect(light.read(), _sintel);

    // Someone else starts watching, and Anna stops.
    playing = [_session('s2', 'Cosmos Laundromat', 'jf-cosmos')];
    await tester.pump(streamSessionsInterval);
    await _settle(tester);

    expect(reads, 2);
    expect(streams(), '1');
    expect(find.textContaining('Sintel'), findsNothing);
    expect(find.textContaining('Cosmos Laundromat'), findsOneWidget);
    expect(light.read(), _cosmos);

    // Both at once: the figure and the list still agree.
    playing = [
      _session('s1', 'Sintel', 'jf-sintel'),
      _session('s2', 'Cosmos Laundromat', 'jf-cosmos'),
    ];
    await tester.pump(streamSessionsInterval);
    await _settle(tester);

    expect(streams(), '2');
    expect(find.textContaining('Sintel'), findsOneWidget);
    expect(find.textContaining('Cosmos Laundromat'), findsOneWidget);

    // Nobody: no figure of a stream, no row, the lamp.
    playing = [];
    await tester.pump(streamSessionsInterval);
    await _settle(tester);

    expect(streams(), '0');
    expect(find.textContaining('Sintel'), findsNothing);
    expect(find.textContaining('Cosmos Laundromat'), findsNothing);
    expect(light.read(), isNull);

    // Off screen, the clock stops: no read while the page is gone.
    await tester.pumpWidget(const SizedBox());
    final settled = reads;
    await tester.pump(streamSessionsInterval * 3);
    expect(reads, settled);
  });
}

/// Lets the reads land and the page redraw. Not `pumpAndSettle`: a card
/// playing something animates for as long as it plays.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

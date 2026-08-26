import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'key-4k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'key-hd',
);

RadarrMovie _movie(String title) =>
    RadarrMovie.fromJson({'id': 42, 'title': title, 'year': 2024});

/// Records which connection each read was keyed on.
final _asked = <String>[];

Future<void> _pump(WidgetTester tester, {String? instanceId}) async {
  _asked.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_fourK, _hd]),
        ),
        movieDetailForProvider.overrideWith((ref, item) async {
          _asked.add(item.instanceId);
          return _movie(
            item.instanceId == 'radarr-hd11111' ? 'HD cut' : '4K cut',
          );
        }),
        radarrQueueSnapshotForProvider.overrideWith(
          (ref, id) => ArrQueueSnapshot.empty,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MovieDetailScreen(
            movieId: 42,
            heroTag: 'movie-42',
            instanceId: instanceId,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a page with no ?i= reads through the lens', (tester) async {
    await _pump(tester);

    expect(_asked, ['radarr']);
    expect(find.text('4K cut'), findsAtLeastNWidgets(1));
  });

  testWidgets('a borrowed page reads the connection its route names', (
    tester,
  ) async {
    // The shape a multi-connection search produces: the lens is still on 4K and
    // the page belongs to HD. Every source on the page has to agree with the
    // route, not with the lens — a page that fetched the right film and then
    // badged it with the other server's queue would look entirely correct.
    await _pump(tester, instanceId: 'radarr-hd11111');

    expect(_asked, ['radarr-hd11111']);
    expect(find.text('HD cut'), findsAtLeastNWidgets(1));
    expect(find.text('4K cut'), findsNothing);
  });
}

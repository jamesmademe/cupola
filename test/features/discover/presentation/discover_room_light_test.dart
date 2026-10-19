import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_room_light.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _seerr = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  label: '',
  url: 'http://seerr.lan:5055',
  credential: 'k',
);

MediaPreview _title(int id, String poster) => MediaPreview(
  id: id,
  title: 'Title $id',
  mediaType: 'movie',
  posterPath: poster,
);

void main() {
  test('Discover waits for Trending, then offers its door\'s three '
      'pictures in order', () async {
    final trending = Completer<List<MediaPreview>>();
    final container = ProviderContainer(
      overrides: [
        hasCalendarProvider.overrideWith((ref) => false),
        activeInstanceProvider.overrideWith(
          (ref, service) => service == ServiceKey.seerr ? _seerr : null,
        ),
        atriumTrendingProvider.overrideWith((ref) => trending.future),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(discoverRoomSourcesProvider, (_, _) {});
    addTearDown(sub.close);

    expect(sub.read(), isNull, reason: 'Trending has not answered');

    trending.complete([
      _title(1, '/one.jpg'),
      _title(2, '/two.jpg'),
      _title(3, '/three.jpg'),
      _title(4, '/four.jpg'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await container.pump();

    expect(sub.read(), [
      'https://image.tmdb.org/t/p/w92/one.jpg',
      'https://image.tmdb.org/t/p/w154/two.jpg',
      'https://image.tmdb.org/t/p/w154/three.jpg',
    ]);
  });

  test('with no Seerr and no calendar there is nothing to choose from', () {
    final container = ProviderContainer(
      overrides: [
        hasCalendarProvider.overrideWith((ref) => false),
        activeInstanceProvider.overrideWith((ref, service) => null),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(discoverRoomSourcesProvider), isEmpty);
    expect(container.read(discoverRoomLightProvider), isNull);
  });
}

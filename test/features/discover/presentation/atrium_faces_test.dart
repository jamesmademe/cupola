import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';

import '../../../test_helpers/fake_services.dart';

/// The faces on the atrium's People door: one read, of the first trending
/// title.
void main() {
  Future<List<String>> faces(Map<String, dynamic> details) async {
    final container = ProviderContainer(
      overrides: [
        atriumTrendingProvider.overrideWith(
          (ref) async => const [
            MediaPreview(id: 10, title: 'Sintel', mediaType: 'movie'),
            MediaPreview(id: 11, title: 'Spring', mediaType: 'movie'),
          ],
        ),
        seerrServiceProvider.overrideWithValue(
          FakeSeerrService(movieDetails: details),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(atriumFacesProvider.future);
  }

  test(
    'the cast first, then the director, those with a photo, three at most',
    () async {
      expect(
        await faces({
          'credits': {
            'cast': [
              {'id': 1, 'name': 'Halina Reijn', 'profilePath': '/a.jpg'},
              {'id': 2, 'name': 'Thom Hoffman', 'profilePath': null},
              {'id': 3, 'name': 'Derek de Lint', 'profilePath': '/c.jpg'},
            ],
            'crew': [
              {
                'id': 4,
                'name': 'Colin Levy',
                'job': 'Director',
                'profilePath': '/d.jpg',
              },
              {'id': 5, 'name': 'Ton Roosendaal', 'job': 'Producer'},
            ],
          },
        }),
        ['/a.jpg', '/c.jpg', '/d.jpg'],
      );
    },
  );

  test('a title with no faces gives the door none', () async {
    expect(await faces({'credits': <String, dynamic>{}}), isEmpty);
  });
}

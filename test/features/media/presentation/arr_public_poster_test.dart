import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/arr_public_poster.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';

const _poster = 'https://image.tmdb.org/t/p/original/fight-club.jpg';

const _settings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '',
      url: 'https://radarr.lan:7878',
      credential: 'k',
    ),
  ],
);

RadarrMovie _fightClub() => RadarrMovie.fromJson({
  'id': 1,
  'title': 'Fight Club',
  'tmdbId': 550,
  'year': 1999,
  // As decoded JSON is: a list of anything.
  'images': <dynamic>[
    {
      'coverType': 'poster',
      'url': '/MediaCover/1/poster.jpg',
      'remoteUrl': _poster,
    },
  ],
});

/// Radarr holding Fight Club as its movie 1.
class _Radarr extends FakeRadarrService {
  @override
  Future<RadarrMovie?> getMovieOrThrow(int movieId) async =>
      movieId == 1 ? _fightClub() : null;

  @override
  Future<RadarrMovie?> getMovieByTmdbId(int tmdbId) async =>
      tmdbId == 550 ? _fightClub() : null;
}

ProviderContainer _container() {
  final radarr = _Radarr();
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      radarrServiceForProvider.overrideWith((ref, id) => radarr),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a movie Radarr holds by TMDB\'s id lends its remote poster', () async {
    final container = _container();
    expect(
      await container.read(
        arrPublicPosterProvider(const MediaKey.movie(550)).future,
      ),
      _poster,
    );
    expect(
      await container.read(
        arrPublicPosterProvider(const MediaKey.movie(603)).future,
      ),
      isNull,
    );
  });

  test('a title named by Radarr\'s own id lends its poster only when the '
      'names agree', () async {
    final container = _container();
    expect(
      await container.read(
        arrPublicPosterByIdProvider((
          service: ServiceKey.radarr,
          id: 1,
          title: 'Fight club',
        )).future,
      ),
      _poster,
      reason: 'the same title, spelled another way',
    );
    expect(
      await container.read(
        arrPublicPosterByIdProvider((
          service: ServiceKey.radarr,
          id: 1,
          title: 'The Matrix',
        )).future,
      ),
      isNull,
      reason: 'the same id on another Radarr is another movie',
    );
  });
}

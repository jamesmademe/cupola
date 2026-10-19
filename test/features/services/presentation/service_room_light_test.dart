import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/media/presentation/arr_public_poster.dart';
import 'package:cupola/features/services/presentation/service_room_light.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_session_poster.dart';

const _sintel = 'https://image.tmdb.org/t/p/original/sintel.jpg';
const _cosmos = 'https://artworks.thetvdb.com/cosmos.jpg';

const _settings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'jf',
      service: ServiceKey.jellyfin,
      label: '',
      url: 'http://jellyfin.lan:8096',
      credential: 'k',
    ),
    ServiceInstance(
      id: 'bz',
      service: ServiceKey.bazarr,
      label: '',
      url: 'http://bazarr.lan:6767',
      credential: 'k',
    ),
  ],
);

StreamSession _playing(String? titleId) => StreamSession(
  id: 's1',
  userName: 'Anna',
  title: 'Sintel',
  subtitle: null,
  deviceLabel: 'Living room TV',
  posterPath: '/Items/jf-sintel/Images/Primary',
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.4,
  isPaused: false,
  titleId: titleId,
);

ProviderContainer _container({
  List<StreamSession> sessions = const [],
  List<BazarrWantedItem> wanted = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      streamSessionsForProvider.overrideWith((ref, key) async => sessions),
      streamSessionPosterProvider.overrideWith(
        (ref, title) async => title.titleId == 'jf-sintel' ? _sintel : null,
      ),
      bazarrDashboardWantedProvider.overrideWith((ref) async => wanted),
      arrPublicPosterByIdProvider.overrideWith(
        (ref, title) async =>
            title.service == ServiceKey.sonarr && title.id == 7
            ? _cosmos
            : null,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<String?> _source(ProviderContainer container, ServiceKey service) async {
  final sub = container.listen(serviceRoomSourceProvider(service), (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return sub.read();
}

void main() {
  test('a media server\'s room is lit by what it plays, through the arrs\' '
      'public poster', () async {
    expect(
      await _source(
        _container(sessions: [_playing('jf-sintel')]),
        ServiceKey.jellyfin,
      ),
      _sintel,
    );
  });

  test('nothing playing, or a title no arr holds, is the lamp', () async {
    expect(await _source(_container(), ServiceKey.jellyfin), isNull);
    expect(
      await _source(
        _container(sessions: [_playing('jf-other')]),
        ServiceKey.jellyfin,
      ),
      isNull,
    );
  });

  test(
    'Bazarr\'s room is lit by the first title it wants subtitles for',
    () async {
      const episode = BazarrWantedItem(
        seriesTitle: 'Cosmos Laundromat',
        episodeNumber: '2x4',
        sonarrSeriesId: 7,
        sonarrEpisodeId: 70,
      );
      expect(
        await _source(_container(wanted: [episode]), ServiceKey.bazarr),
        _cosmos,
      );
    },
  );

  test('a wanted row names its title by the series, else by the movie', () {
    expect(
      bazarrArrTitleOf(
        const BazarrWantedItem(
          seriesTitle: 'Cosmos Laundromat',
          sonarrSeriesId: 7,
        ),
      ),
      (service: ServiceKey.sonarr, id: 7, title: 'Cosmos Laundromat'),
    );
    expect(
      bazarrArrTitleOf(const BazarrWantedItem(title: 'Sintel', radarrId: 3)),
      (service: ServiceKey.radarr, id: 3, title: 'Sintel'),
    );
    expect(bazarrArrTitleOf(const BazarrWantedItem(radarrId: 3)), isNull);
  });
}

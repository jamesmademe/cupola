import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_units.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

StreamSession _session({
  String user = 'Anna',
  String title = 'Sintel',
  String? subtitle = '2010',
  String device = 'Living room TV',
  bool paused = false,
  Duration? remaining = const Duration(minutes: 9),
  double? progress = 0.4,
}) => StreamSession(
  id: 's1',
  userName: user,
  title: title,
  subtitle: subtitle,
  deviceLabel: device,
  posterPath: null,
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: progress,
  isPaused: paused,
  remaining: remaining,
);

/// The words of the Home's Now playing module.
void main() {
  test('who and what; an episode by its code, never its name', () {
    expect(nowPlayingTitle(_session()), 'Anna\u00A0· Sintel');
    expect(
      nowPlayingTitle(
        _session(
          title: 'Cosmos Laundromat',
          subtitle: 'S2 E3\u00A0· The Second Cycle',
        ),
      ),
      'Anna\u00A0· Cosmos Laundromat\u00A0· S2 E3',
    );
    expect(nowPlayingTitle(_session(user: ' ')), 'Sintel');
  });

  test('where, and how long is left; Stopped while the player holds it', () {
    expect(nowPlayingLine(_session()), 'Living room TV\u00A0· 9\u00A0min left');
    expect(
      nowPlayingLine(_session(paused: true)),
      'Living room TV\u00A0· Stopped\u00A0· 9\u00A0min left',
    );
    expect(nowPlayingLine(_session(remaining: null)), 'Living room TV');
  });

  test('the disc carries the first letter of who is watching', () {
    expect(nowPlayingInitial(_session(user: 'anna')), 'A');
    expect(nowPlayingInitial(_session(user: '')), '?');
  });

  test('Jellyfin\'s ticks give the time left, never less than none', () {
    // A tick is 100 ns: 15 min of runtime, 6 min in.
    expect(
      jellyfinRemainingFromTicks(
        position: 6 * 60 * 10000000,
        runtime: 15 * 60 * 10000000,
      ),
      const Duration(minutes: 9),
    );
    expect(
      jellyfinRemainingFromTicks(position: 20, runtime: 10),
      Duration.zero,
    );
    expect(jellyfinRemainingFromTicks(position: null, runtime: 10), isNull);
    expect(jellyfinRemainingFromTicks(position: 1, runtime: 0), isNull);
  });
}
